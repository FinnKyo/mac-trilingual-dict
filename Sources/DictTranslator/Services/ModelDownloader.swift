import Foundation
import CryptoKit

/// 本地翻译模型的一键下载。边下边写入磁盘上的「.part」文件，暂停、断网、退出 App 后都能从断点继续（HTTP Range）；
/// 下载前检查磁盘空间，完成后校验 SHA-256 再改名为正式文件
@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    static let shared = ModelDownloader()

    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case paused(received: Int64, total: Int64)
        case verifying
        case failed(String)
    }

    @Published private(set) var phases: [LocalModel: Phase] = [:]
    @Published private(set) var installed: Set<LocalModel> = []

    /// 一次下载请求。字段只在 delegate 的串行队列上读写（model、url 创建后不变）
    private final class Job: @unchecked Sendable {
        let model: LocalModel
        let handle: FileHandle
        var received: Int64
        var status = 0
        var lastReport = Date.distantPast
        init(model: LocalModel, handle: FileHandle, received: Int64) {
            self.model = model
            self.handle = handle
            self.received = received
        }
    }

    private var tasks: [LocalModel: URLSessionDataTask] = [:]
    private var sourceIndex: [LocalModel: Int] = [:]
    /// 用户主动暂停 / 取消的任务，结束回调里不当作失败
    private var stoppedByUser: Set<Int> = []

    private let jobsLock = NSLock()
    nonisolated(unsafe) private var jobs: [Int: Job] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 24
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    override init() {
        super.init()
        refreshInstalled()
    }

    func phase(_ model: LocalModel) -> Phase { phases[model] ?? .idle }

    /// 重新检查磁盘上的文件（用户可能在 Finder 里删掉了模型）；上次没下完的显示为「已暂停」
    func refreshInstalled() {
        installed = Set(LocalModel.allCases.filter(\.isInstalled))
        for model in LocalModel.allCases where tasks[model] == nil {
            if installed.contains(model) {
                if case .failed = phase(model) { continue }
                phases[model] = .idle
            } else if let size = partSize(model), size > 0 {
                if case .failed = phase(model) { continue }
                phases[model] = .paused(received: size, total: model.byteSize)
            } else if case .paused = phase(model) {
                phases[model] = .idle
            }
        }
    }

    func download(_ model: LocalModel) {
        guard tasks[model] == nil, !installed.contains(model) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: LocalModel.directory, withIntermediateDirectories: true)
        let part = model.partURL
        if !fm.fileExists(atPath: part.path) { fm.createFile(atPath: part.path, contents: nil) }
        var offset = partSize(model) ?? 0
        if offset > model.byteSize {
            try? fm.removeItem(at: part)
            fm.createFile(atPath: part.path, contents: nil)
            offset = 0
        }

        let needed = model.byteSize - offset
        if let free = freeSpace(), free < needed + 200_000_000 {
            phases[model] = .failed("磁盘空间不足：还需要 \(bytes(needed + 200_000_000))，当前可用 \(bytes(free))")
            return
        }
        guard let handle = try? FileHandle(forWritingTo: part) else {
            phases[model] = .failed("无法写入模型文件夹")
            return
        }
        _ = try? handle.seekToEnd()

        var request = URLRequest(url: model.downloadURLs[sourceIndex[model] ?? 0])
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        jobsLock.withLock { jobs[task.taskIdentifier] = Job(model: model, handle: handle, received: offset) }
        tasks[model] = task
        phases[model] = .downloading(received: offset, total: model.byteSize)
        task.resume()
    }

    func pause(_ model: LocalModel) {
        guard let task = tasks.removeValue(forKey: model) else { return }
        stoppedByUser.insert(task.taskIdentifier)
        task.cancel()
        phases[model] = .paused(received: partSize(model) ?? 0, total: model.byteSize)
    }

    /// 取消并删除已下载的部分
    func cancel(_ model: LocalModel) {
        if let task = tasks.removeValue(forKey: model) {
            stoppedByUser.insert(task.taskIdentifier)
            task.cancel()
        }
        try? FileManager.default.removeItem(at: model.partURL)
        sourceIndex[model] = nil
        phases[model] = .idle
    }

    func delete(_ model: LocalModel) {
        cancel(model)
        HyMTService.unload(model)
        try? FileManager.default.removeItem(at: model.fileURL)
        refreshInstalled()
    }

    // MARK: - 下载结束

    private func finished(_ model: LocalModel, taskId: Int, status: Int, error: Error?) {
        if stoppedByUser.remove(taskId) != nil { return }
        guard tasks[model]?.taskIdentifier == taskId else { return }
        tasks[model] = nil
        let size = partSize(model) ?? 0

        let ok = (200..<300).contains(status)
        if let error, ok {
            // 下载途中断网等：已下载的部分保留在磁盘上，点「继续」接着下载
            phases[model] = .failed("下载中断（\(error.friendlyMessage)），已下载 \(bytes(size))，可继续")
            return
        }
        guard ok else {
            // 这个下载源连不上或不可用：换下一个源从断点继续（各源文件相同，SHA-256 一致）
            let next = (sourceIndex[model] ?? 0) + 1
            if next < model.downloadURLs.count {
                sourceIndex[model] = next
                download(model)
            } else {
                sourceIndex[model] = nil
                phases[model] = .failed(error.map { "下载失败（\($0.friendlyMessage)）" } ?? "下载失败（HTTP \(status)）")
            }
            return
        }
        guard size == model.byteSize else {
            if size > model.byteSize { try? FileManager.default.removeItem(at: model.partURL) }
            phases[model] = .failed("下载的文件不完整（\(bytes(size)) / \(bytes(model.byteSize))），可继续")
            return
        }
        verify(model)
    }

    /// 校验 SHA-256，通过后改名为正式文件
    private func verify(_ model: LocalModel) {
        phases[model] = .verifying
        let part = model.partURL
        Task.detached(priority: .utility) {
            let ok = Self.sha256(of: part) == model.sha256
            await MainActor.run {
                if ok {
                    try? FileManager.default.removeItem(at: model.fileURL)
                    do {
                        try FileManager.default.moveItem(at: part, to: model.fileURL)
                        self.phases[model] = .idle
                    } catch {
                        self.phases[model] = .failed("保存模型失败：\(error.localizedDescription)")
                    }
                } else {
                    try? FileManager.default.removeItem(at: part)
                    self.phases[model] = .failed("文件校验失败，请重新下载")
                }
                self.sourceIndex[model] = nil
                self.refreshInstalled()
            }
        }
    }

    // MARK: - 工具

    private func partSize(_ model: LocalModel) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: model.partURL.path))?[.size] as? Int64
    }

    private func freeSpace() -> Int64? {
        let values = try? LocalModel.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    nonisolated private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { try? handle.read(upToCount: 8 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private func job(_ task: URLSessionTask) -> Job? {
        jobsLock.withLock { jobs[task.taskIdentifier] }
    }
}

extension ModelDownloader: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                                completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let job = job(dataTask) else { completionHandler(.cancel); return }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        job.status = status
        switch status {
        case 206:
            completionHandler(.allow)
        case 200:
            // 服务器不支持断点续传，返回了整个文件：从头写
            if job.received > 0 {
                try? job.handle.truncate(atOffset: 0)
                job.received = 0
            }
            completionHandler(.allow)
        default:
            completionHandler(.cancel)
        }
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let job = job(dataTask) else { return }
        do {
            try job.handle.write(contentsOf: data)
        } catch {
            dataTask.cancel()
            return
        }
        job.received += Int64(data.count)
        let now = Date()
        guard now.timeIntervalSince(job.lastReport) >= 0.2 else { return }
        job.lastReport = now
        let (model, received) = (job.model, job.received)
        Task { @MainActor in
            guard self.tasks[model]?.taskIdentifier == dataTask.taskIdentifier else { return }
            self.phases[model] = .downloading(received: received, total: model.byteSize)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let job = jobsLock.withLock({ jobs.removeValue(forKey: task.taskIdentifier) }) else { return }
        try? job.handle.synchronize()
        try? job.handle.close()
        let status = job.status
        // 状态码不对时是我们自己取消的（completionHandler(.cancel)），不是网络错误；没收到响应（status 0）时保留错误
        let failure: Error? = (200..<300).contains(status) || status == 0 ? error : nil
        let model = job.model
        Task { @MainActor in
            self.finished(model, taskId: task.taskIdentifier, status: status, error: failure)
        }
    }
}
