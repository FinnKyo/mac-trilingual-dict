import Foundation

/// 可下载到本机运行的腾讯混元翻译模型 Hy-MT2（llama.cpp GGUF，Q4_K_M 量化）
/// 文件、大小与 SHA-256 取自官方仓库 tencent/Hy-MT2-*-GGUF（Hugging Face 与 ModelScope 内容一致）
enum LocalModel: String, CaseIterable, Identifiable {
    case hyMT2_7B
    case hyMT2_1_8B

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hyMT2_7B: return "Hy-MT2-7B"
        case .hyMT2_1_8B: return "Hy-MT2-1.8B"
        }
    }

    var subtitle: String {
        switch self {
        case .hyMT2_7B: return "效果更好"
        case .hyMT2_1_8B: return "尺寸小、速度快"
        }
    }

    var fileName: String {
        switch self {
        case .hyMT2_7B: return "Hy-MT2-7B-Q4_K_M.gguf"
        case .hyMT2_1_8B: return "Hy-MT2-1.8B-Q4_K_M.gguf"
        }
    }

    var byteSize: Int64 {
        switch self {
        case .hyMT2_7B: return 4_624_648_896
        case .hyMT2_1_8B: return 1_133_080_448
        }
    }

    var sha256: String {
        switch self {
        case .hyMT2_7B: return "9f96256500f3fc1ab4d64336b58f52a949a95ad7516b0c229476eef782f9f77b"
        case .hyMT2_1_8B: return "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699"
        }
    }

    private var repoName: String {
        switch self {
        case .hyMT2_7B: return "Hy-MT2-7B-GGUF"
        case .hyMT2_1_8B: return "Hy-MT2-1.8B-GGUF"
        }
    }

    /// 下载地址：先 ModelScope（国内快），失败再 Hugging Face
    var downloadURLs: [URL] {
        [
            URL(string: "https://modelscope.cn/models/Tencent-Hunyuan/\(repoName)/resolve/master/\(fileName)")!,
            URL(string: "https://huggingface.co/tencent/\(repoName)/resolve/main/\(fileName)")!,
        ]
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DictTranslator/Models", isDirectory: true)
    }

    var fileURL: URL { Self.directory.appendingPathComponent(fileName) }
    /// 下载中的部分文件（断点续传）
    var partURL: URL { Self.directory.appendingPathComponent(fileName + ".part") }

    /// 已下载完成（下载完成时已校验过 SHA-256，这里只核对大小）
    var isInstalled: Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int64 else { return false }
        return size == byteSize
    }
}
