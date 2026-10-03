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
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKeys.engine) private var engine = TranslationEngine.googleWithFallback.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("快捷键") {
                KeyboardShortcuts.Recorder("输入翻译：", name: .openInput)
                KeyboardShortcuts.Recorder("截图翻译：", name: .screenshot)
                KeyboardShortcuts.Recorder("翻译选中文本：", name: .translateSelection)
            }
            Section("句子翻译引擎") {
                Picker("引擎", selection: $engine) {
                    ForEach(TranslationEngine.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("单词释义固定使用有道词典（英汉、日汉、汉英、汉日）。Google 被限流时会自动暂停 10 分钟改用腾讯交互翻译。系统离线翻译需 macOS 26+，并在「系统设置 › 通用 › 语言与地区 › 翻译语言」下载中文、英语、日语。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    request: { Permissions.requestScreenRecording(); Permissions.openScreenRecordingSettings() }
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
                    Text("• ⌥A 打开输入翻译窗，输入中文 / 英文 / 日文")
                    Text("• 选中任意文字，鼠标移到出现的小图标上即可查看翻译")
                    Text("• ⌥S 框选屏幕区域，识别文字并翻译")
                    Text("• ⌥D 直接翻译当前选中的文字")
                    Text("• 输入任意一种语言，会同时显示另外两种语言的结果")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
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
            }
        }
    }
}
