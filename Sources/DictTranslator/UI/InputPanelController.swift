import AppKit
import SwiftUI

/// ⌥A 输入翻译窗 / 截图翻译结果窗
@MainActor
final class InputPanelController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = InputPanelController()

    let vm = LookupViewModel()
    @Published var pinned = false
    @Published var statusMessage: String?
    @Published var focusToken = 0

    private let width: CGFloat = 480
    /// 结果区最大高度：不超过 520，且保证整个窗口不超出屏幕底部
    @Published private(set) var resultMaxHeight: CGFloat = 520
    private lazy var panel: FloatingPanel = makePanel()
    private var hasPositioned = false

    var isVisible: Bool { panel.isVisible }

    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(size: NSSize(width: width, height: 120))
        p.delegate = self
        p.onCancel = { [weak self] in self?.close() }
        p.level = .floating
        let root = InputTranslatorView(controller: self, vm: vm)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        p.contentView = hosting
        return p
    }

    func toggle() {
        if panel.isVisible, panel.isKeyWindow { close() } else { show() }
    }

    func show(text: String? = nil, status: String? = nil, preferJapanese: Bool = false) {
        statusMessage = status
        if !hasPositioned { positionDefault(); hasPositioned = true }
        else if !pinned { positionDefault() }
        NSApp.activate(ignoringOtherApps: true)
        updateResultMaxHeight()
        panel.makeKeyAndOrderFront(nil)
        // App 激活完成后系统可能把焦点交给其他窗口（如设置窗口），再确认一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.panel.makeKeyAndOrderFront(nil)
            self.focusToken += 1
        }
        if let text {
            vm.lookup(text, preferJapanese: preferJapanese)
        }
        focusToken += 1
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        vm.cancel()
        // 把焦点还给之前的 App
        if NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }) {
            NSApp.hide(nil)
        }
    }

    func updateHeight(_ contentHeight: CGFloat) {
        var frame = panel.frame
        let screenBottom = (panel.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        let h = ceil(min(max(contentHeight, 60), frame.maxY - screenBottom - 4))
        guard abs(frame.height - h) > 0.5 else { return }
        let top = frame.maxY
        frame.size.height = h
        frame.origin.y = top - h
        panel.setFrame(frame, display: true, animate: false)
    }

    private func updateResultMaxHeight() {
        guard let vf = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        // 输入框、标题栏、状态行约占 130pt
        let available = panel.frame.maxY - vf.minY - 8 - 130
        let value = max(120, min(520, available))
        if abs(value - resultMaxHeight) > 0.5 { resultMaxHeight = value }
    }

    private func positionDefault() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screen(containing: mouse) else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - width / 2
        let top = vf.maxY - vf.height * 0.16
        panel.setFrame(NSRect(x: x, y: top - panel.frame.height, width: width, height: panel.frame.height), display: false)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        updateResultMaxHeight()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !pinned else { return }
        // 系统截图、权限弹窗等也会让窗口失去焦点，稍等再判断
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !self.pinned, !self.panel.isKeyWindow else { return }
            self.panel.orderOut(nil)
            self.vm.cancel()
        }
    }
}

struct InputTranslatorView: View {
    @ObservedObject var controller: InputPanelController
    @ObservedObject var vm: LookupViewModel
    @FocusState private var focused: Bool
    @State private var resultHeight: CGFloat = 0
    @State private var debounce: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            inputField
            if let msg = controller.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if vm.hasQuery {
                Divider()
                ScrollView {
                    ResultView(vm: vm, showSource: false)
                        .padding(12)
                        .reportHeight { resultHeight = $0 }
                }
                .frame(height: min(resultHeight, controller.resultMaxHeight))
            }
        }
        .frame(width: 480)
        .background(Theme.panelTint)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.rule))
        .fixedSize(horizontal: false, vertical: true)
        .reportHeight { controller.updateHeight($0) }
        .onChange(of: controller.focusToken) { _, _ in focused = true }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "character.book.closed.fill")
                .foregroundStyle(Theme.accent)
                .font(.system(size: 12))
            Text("中日英辞典").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            WindowDragArea().frame(maxWidth: .infinity).frame(height: 22)
            IconButton(systemName: "camera.viewfinder", help: "截图翻译") {
                AppController.shared.startScreenshot()
            }
            IconButton(systemName: controller.pinned ? "pin.fill" : "pin", help: controller.pinned ? "取消固定" : "固定窗口（失去焦点不关闭）") {
                controller.pinned.toggle()
            }
            IconButton(systemName: "xmark", help: "关闭 (Esc)") { controller.close() }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var inputField: some View {
        HStack(alignment: .top, spacing: 6) {
            TextField("输入中文 / English / 日本語，回车翻译", text: $vm.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit { submit() }
                .onChange(of: vm.inputText) { _, newValue in scheduleLookup(newValue) }
            if !vm.inputText.isEmpty {
                IconButton(systemName: "xmark.circle.fill", help: "清空") {
                    debounce?.cancel()
                    vm.clear()
                    controller.statusMessage = nil
                    focused = true
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submit() {
        debounce?.cancel()
        let t = vm.inputText
        if QueryClassifier.normalize(t) != vm.text || !vm.hasQuery {
            vm.lookup(t)
        }
    }

    private func scheduleLookup(_ value: String) {
        debounce?.cancel()
        let normalized = QueryClassifier.normalize(value)
        guard normalized != vm.text else { return }
        if normalized.isEmpty { vm.clear(); return }
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, QueryClassifier.normalize(vm.inputText) == normalized else { return }
            vm.lookup(value)
        }
    }
}
