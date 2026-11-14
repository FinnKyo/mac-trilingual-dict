import SwiftUI
import KeyboardShortcuts
import ServiceManagement

enum SettingsTab: Hashable {
    case general, selection, permissions
}

@MainActor
final class SettingsState: ObservableObject {
    static let shared = SettingsState()
    @Published var tab: SettingsTab = .general
    @Published var accessibility = Permissions.isAccessibilityTrusted
    @Published var screenRecording = Permissions.hasScreenRecording

    func refreshPermissions() {
        let a = Permissions.isAccessibilityTrusted
        let s = Permissions.hasScreenRecording
        if a != accessibility {
            accessibility = a
            // 授权后重新注册全局监听（键盘事件监听需要授权后注册才生效）
            if a {
                SelectionController.shared.stop()
                SelectionController.shared.start()
            }
        }
        if s != screenRecording { screenRecording = s }
    }
}

struct SettingsView: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        TabView(selection: $state.tab) {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            SelectionSettings()
                .tabItem { Label("划词", systemImage: "cursorarrow.rays") }
                .tag(SettingsTab.selection)
            PermissionSettings(state: state)
                .tabItem { Label("权限", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @State private var order = TranslationEngine.order
    @State private var disabled = TranslationEngine.disabled
    @ObservedObject private var downloader = ModelDownloader.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("快捷键") {
                KeyboardShortcuts.Recorder("输入翻译：", name: .openInput)
                KeyboardShortcuts.Recorder("截图翻译：", name: .screenshot)
                KeyboardShortcuts.Recorder("翻译选中文本：", name: .translateSelection)
            }
            Section {
                ForEach(Array(order.enumerated()), id: \.element) { i, e in
                    EngineRow(engine: e, index: i, count: order.count,
                              enabled: enabledBinding(e), move: { move(e, by: $0) },
                              downloader: downloader)
                }
                if let note = chainNote {
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("句子翻译服务")
            } footer: {
                Text("从上到下依次尝试已勾选的服务：排在前面的出错或未下载时自动换用下一个。本地模型为腾讯混元翻译模型 Hy-MT2，下载后完全离线运行；7B 效果更好，建议 16 GB 以上内存。单词查询使用词典（日语：MOJi 辞書、デジタル大辞泉；英语：有道词典），不受此设置影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("其他") {
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        // 失败后回滚开关会再次触发这里，此时状态已一致，不要重复操作（否则会覆盖原始错误）
                        guard on != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        // 用户可能在 Finder 里删掉了模型文件，打开设置、切回 App 时重新检查
        .onAppear { downloader.refreshInstalled() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            downloader.refreshInstalled()
        }
    }

    private func enabledBinding(_ e: TranslationEngine) -> Binding<Bool> {
        Binding(get: { !disabled.contains(e) }, set: { on in
            if on { disabled.remove(e) } else { disabled.insert(e) }
            TranslationEngine.save(order: order, disabled: disabled)
        })
    }

    private func move(_ e: TranslationEngine, by offset: Int) {
        guard let i = order.firstIndex(of: e), order.indices.contains(i + offset) else { return }
        order.swapAt(i, i + offset)
        TranslationEngine.save(order: order, disabled: disabled)
    }

    /// 实际会先用哪个服务的提示：排在前面的已勾选服务暂时不能用时说明
    private var chainNote: String? {
        let chain = order.filter { !disabled.contains($0) }
        guard let first = chain.first else { return "没有勾选任何服务，句子将无法翻译。" }
        let available: (TranslationEngine) -> Bool = { e in
            e.localModel.map(downloader.installed.contains) ?? true
        }
        guard !available(first) else { return nil }
        let reason = "尚未下载"
        if let next = chain.first(where: available) {
            return "\(first.shortName) \(reason)，暂时使用 \(next.shortName)。"
        }
        return "\(first.shortName) \(reason)，且没有其他可用的服务，句子将无法翻译。"
    }
}

/// 一个翻译服务：勾选是否启用、上下移动调整顺序 + 名称；本地模型另有状态与下载 / 暂停 / 继续 / 删除
private struct EngineRow: View {
    let engine: TranslationEngine
    let index: Int
    let count: Int
    @Binding var enabled: Bool
    let move: (Int) -> Void
    @ObservedObject var downloader: ModelDownloader
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(isOn: $enabled) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(engine.title).foregroundStyle(enabled ? .primary : .secondary)
                        if let model = engine.localModel { status(model) }
                    }
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            if let model = engine.localModel { actions(model) }
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .help("上移（优先使用）")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == count - 1)
                    .help("下移")
            }
            .buttonStyle(.borderless)
        }
        .confirmationDialog("删除 \(engine.localModel?.displayName ?? "")？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { engine.localModel.map(downloader.delete) }
        } message: {
            Text("将释放 \(engine.localModel?.sizeText ?? "") 磁盘空间，之后需要重新下载才能使用。")
        }
    }

    @ViewBuilder private func status(_ model: LocalModel) -> some View {
        switch downloader.phase(model) {
        case .downloading(let received, let total):
            ProgressView(value: Double(received), total: Double(max(total, 1)))
                .frame(maxWidth: 260)
            Text("正在下载 \(bytes(received)) / \(bytes(total))").font(.caption).foregroundStyle(.secondary)
        case .paused(let received, let total):
            ProgressView(value: Double(received), total: Double(max(total, 1)))
                .frame(maxWidth: 260)
            Text("已暂停 \(bytes(received)) / \(bytes(total))").font(.caption).foregroundStyle(.secondary)
        case .verifying:
            Text("正在校验文件…").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .idle:
            Text(downloader.installed.contains(model) ? "已下载 · \(model.subtitle)" : "\(model.subtitle) · \(model.sizeText)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func actions(_ model: LocalModel) -> some View {
        switch downloader.phase(model) {
        case .downloading:
            Button("暂停") { downloader.pause(model) }
            Button("取消") { downloader.cancel(model) }
        case .paused:
            Button("继续") { downloader.download(model) }
            Button("取消") { downloader.cancel(model) }
        case .verifying:
            ProgressView().controlSize(.small)
        case .idle, .failed:
            if downloader.installed.contains(model) {
                Button("删除") { confirmDelete = true }
            } else if isFailed(model) {
                Button("继续") { downloader.download(model) }
                Button("取消") { downloader.cancel(model) }
            } else {
                Button("下载") { downloader.download(model) }
            }
        }
    }

    private func isFailed(_ model: LocalModel) -> Bool {
        if case .failed = downloader.phase(model) { return true }
        return false
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

private struct SelectionSettings: View {
    @AppStorage(SettingsKeys.selectionEnabled) private var enabled = true
    @AppStorage(SettingsKeys.iconDismissDelay) private var delay = 4.0
    @State private var blacklist: [String] = SettingsKeys.blacklistedBundleIDs
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Toggle("启用划词翻译（选中文字后显示翻译图标）", isOn: $enabled)
                HStack {
                    Text("图标自动消失：\(String(format: "%.1f", delay)) 秒")
                    Slider(value: $delay, in: 1.5...10, step: 0.5)
                }
            }
            Section("在以下 App 中不显示划词图标") {
                List(selection: $selection) {
                    ForEach(blacklist, id: \.self) { bid in
                        HStack {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 16, height: 16)
                                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                            } else {
                                Image(systemName: "app.dashed").frame(width: 16, height: 16)
                                Text(bid)
                            }
                            Spacer()
                            Text(bid).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(bid)
                    }
                }
                .frame(minHeight: 140)
                HStack {
                    Button("添加 App…") { addApp() }
                    Button("移除") {
                        if let s = selection { blacklist.removeAll { $0 == s }; save() }
                    }
                    .disabled(selection == nil)
                    Spacer()
                    Button("恢复默认") { blacklist = SettingsKeys.defaultBlacklist; save() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bid = Bundle(url: url)?.bundleIdentifier, !blacklist.contains(bid) {
                blacklist.append(bid)
            }
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(blacklist, forKey: SettingsKeys.blacklist)
    }
}

private struct PermissionSettings: View {
    @ObservedObject var state: SettingsState

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "辅助功能",
                    detail: "用于划词翻译与「翻译选中文本」：读取其他 App 中选中的文字。",
                    granted: state.accessibility,
                    request: { Permissions.promptAccessibility(); Permissions.openAccessibilitySettings() }
                )
                permissionRow(
                    title: "屏幕与系统音频录制",
                    detail: "用于截图翻译。授权后需要重新打开本 App 才能生效。",
                    granted: state.screenRecording,
                    request: { Permissions.requestScreenRecording(); Permissions.openScreenRecordingSettings() },
                    // 屏幕录制权限要重新打开 App 才生效（系统不会通知），提供一键重启
                    relaunch: true
                )
            } header: {
                Text("首次使用请授予以下权限")
            } footer: {
                Text("如果已勾选但仍显示未授权（例如更新了 App），请在系统设置中先移除「中日英辞典」再重新添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("使用方法") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• \(shortcut(.openInput)) 打开输入翻译窗，输入中文 / 英文 / 日文")
                    Text("• 选中任意文字，鼠标移到出现的小图标上即可查看翻译")
                    Text("• \(shortcut(.screenshot)) 框选屏幕区域，识别文字并翻译")
                    Text("• \(shortcut(.translateSelection)) 直接翻译当前选中的文字")
                    Text("• 输入中文同时显示英语和日语，输入英语或日语显示中文")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    /// 显示用户当前设置的快捷键（可在「通用」中修改）
    private func shortcut(_ name: KeyboardShortcuts.Name) -> String {
        KeyboardShortcuts.getShortcut(for: name)?.description ?? "（未设置快捷键）"
    }

    private func permissionRow(title: String, detail: String, granted: Bool, request: @escaping () -> Void,
                               relaunch: Bool = false) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("已授权").foregroundStyle(.secondary)
            } else {
                Button("去授权", action: request)
                if relaunch {
                    Button("重新打开 App") { AppController.shared.relaunch() }
                        .help("已在系统设置中授权后点这里，权限才会生效")
                }
            }
        }
    }
}
