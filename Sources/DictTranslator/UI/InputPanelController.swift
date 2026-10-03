import AppKit
import SwiftUI

/// 输入翻译窗：⌥A 输入、截图 / ⌥D / 划词的结果都显示在这里（划词时跟着选区，其余在屏幕右上角）
@MainActor
final class InputPanelController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = InputPanelController()

    let vm = LookupViewModel()
    @Published var pinned = false
    @Published var statusMessage: String?
    @Published var focusToken = 0
    /// 下一次聚焦输入框时把光标放在末尾（划词、截图带入文字时，方便直接修改）；否则保持系统默认（全选）
    private(set) var caretAtEnd = false

    static let width: CGFloat = 480
    private var width: CGFloat { Self.width }
    /// 输入框、标题栏、状态行占用的高度
    private let chromeHeight: CGFloat = 130
    private let preferredResultHeight: CGFloat = 520
    /// 结果区最大高度：不超过 520，且保证整个窗口不超出屏幕
    @Published private(set) var resultMaxHeight: CGFloat = 520
    private lazy var panel: FloatingPanel = makePanel()
    private var hasPositioned = false

    /// 窗口哪条边固定：窗口随内容变高时往另一侧长
    private enum Anchor {
        case top(CGFloat)      // 顶边固定，向下长（屏幕右上角、选区下方、拖动之后）
        case bottom(CGFloat)   // 底边固定，向上长（选区上方）
    }
    private var anchor: Anchor = .top(0)
    private var originX: CGFloat = 0
    private var visibleFrame: NSRect = .zero
    /// 当前位置下窗口最高能有多高
    private var availableHeight: CGFloat = 600
    /// 程序自己移动窗口时 windowDidMove 也会触发，要和用户拖动区分开
    private var isPlacing = false

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

    /// selection：划词时的选区（或小图标）位置，窗口跟着它走；为 nil（快捷键、截图、菜单）时放在屏幕右上角。
    /// 窗口固定（pinned）后保持用户放的位置
    func show(text: String? = nil, status: String? = nil, caretAtEnd: Bool = false, near selection: NSRect? = nil) {
        statusMessage = status
        self.caretAtEnd = caretAtEnd
        if !(pinned && hasPositioned) {
            if let selection { place(near: selection) } else { placeTopRight() }
            hasPositioned = true
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // App 激活完成后系统可能把焦点交给其他窗口（如设置窗口），再确认一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.panel.makeKeyAndOrderFront(nil)
            self.focusToken += 1
        }
        if let text {
            vm.lookup(text)
        }
        focusToken += 1
        if caretAtEnd { placeCaretAtEnd() }
    }

    /// 聚焦后输入框默认全选；从划词 / 截图带入的文字，光标放到末尾更方便修改。
    /// 文字赋值、聚焦都是异步生效的，会重置选区，所以等它们落定后再放，并补一次
    private func placeCaretAtEnd() {
        for delay in [0.1, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.panel.isVisible, let editor = self.panel.firstResponder as? NSTextView else { return }
                let end = editor.string.utf16.count
                if editor.selectedRange() != NSRange(location: end, length: 0) {
                    editor.setSelectedRange(NSRange(location: end, length: 0))
                }
            }
        }
    }

    #if DEBUG
    /// 调试：向输入窗发送按键、读取状态（验证划词后能否直接编辑）
    func debugKey(_ chars: String) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0) else { continue }
            panel.sendEvent(e)
        }
    }

    /// 调试：模拟 ⌘+字母，走 NSApp.sendEvent（和真实按键一样会先经过主菜单的快捷键）
    func debugCommand(_ key: String) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil, characters: key,
                                           charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0) else { continue }
            NSApp.sendEvent(e)
        }
    }

    func debugState() -> String {
        let editor = panel.firstResponder as? NSTextView
        let caret = editor.map { "\($0.selectedRange().location),\($0.selectedRange().length)/\($0.string.utf16.count)" } ?? "-"
        return "frame=\(NSStringFromRect(panel.frame)) maxResult=\(Int(resultMaxHeight)) visible=\(panel.isVisible) key=\(panel.isKeyWindow) text=\(vm.text) input=\(vm.inputText) lang=\(vm.sourceLang) caret=\(caret) responder=\(type(of: (panel.firstResponder ?? panel) as AnyObject))"
    }
    #endif

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
        let h = ceil(min(max(contentHeight, 60), availableHeight))
        let target = frame(height: h)
        guard abs(panel.frame.height - target.height) > 0.5 || abs(panel.frame.minY - target.minY) > 0.5 else { return }
        setFrame(target)
    }

    // MARK: - 位置

    private func frame(height h: CGFloat) -> NSRect {
        var y: CGFloat
        switch anchor {
        case .top(let top): y = top - h
        case .bottom(let bottom): y = bottom
        }
        // 最后保证完全落在屏幕可见范围内
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - h)
        return NSRect(x: originX, y: y, width: width, height: h)
    }

    private func setFrame(_ rect: NSRect) {
        isPlacing = true
        panel.setFrame(rect, display: true, animate: false)
        isPlacing = false
    }

    private func apply(_ anchor: Anchor, x: CGFloat, visibleFrame vf: NSRect, availableHeight available: CGFloat) {
        self.anchor = anchor
        originX = x
        visibleFrame = vf
        availableHeight = min(available, chromeHeight + preferredResultHeight)
        resultMaxHeight = max(120, availableHeight - chromeHeight)
        setFrame(frame(height: min(panel.frame.height, availableHeight)))
    }

    /// ⌥A / ⌥S / ⌥D / 菜单：屏幕右上角（鼠标所在的屏幕）
    private func placeTopRight() {
        let screen = NSScreen.screen(containing: NSEvent.mouseLocation)
        let vf = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)).insetBy(dx: 12, dy: 12)
        apply(.top(vf.maxY), x: vf.maxX - width, visibleFrame: vf, availableHeight: vf.height)
    }

    /// 划词：在选区下方；下方放不下就放上方；上下都不够则贴着屏幕放，可以盖住选区
    private func place(near selection: NSRect) {
        let screen = NSScreen.screen(containing: NSPoint(x: selection.midX, y: selection.midY))
        let vf = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)).insetBy(dx: 4, dy: 4)
        let x = min(max(selection.minX - 16, vf.minX), vf.maxX - width)

        let desired = chromeHeight + preferredResultHeight
        let spaceBelow = selection.minY - 4 - vf.minY
        let spaceAbove = vf.maxY - (selection.maxY + 4)
        let minUseful: CGFloat = 320
        if spaceBelow >= desired || (spaceBelow >= spaceAbove && spaceBelow >= minUseful) {
            apply(.top(selection.minY - 4), x: x, visibleFrame: vf, availableHeight: spaceBelow)
        } else if spaceAbove >= minUseful {
            apply(.bottom(selection.maxY + 4), x: x, visibleFrame: vf, availableHeight: spaceAbove)
        } else {
            apply(.top(min(selection.minY - 4 + desired / 2, vf.maxY)), x: x, visibleFrame: vf, availableHeight: vf.height)
        }
    }

    // MARK: NSWindowDelegate

    /// 用户拖动窗口后：顶边固定在当前位置、向下长，并按新位置重算最大高度（不移动窗口，允许拖到屏幕边缘）
    func windowDidMove(_ notification: Notification) {
        guard !isPlacing else { return }
        let f = panel.frame
        let vf = ((panel.screen ?? NSScreen.main)?.visibleFrame ?? f).insetBy(dx: 4, dy: 4)
        anchor = .top(f.maxY)
        originX = f.minX
        visibleFrame = vf
        availableHeight = min(max(f.maxY - vf.minY, 200), chromeHeight + preferredResultHeight)
        resultMaxHeight = max(120, availableHeight - chromeHeight)
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
        .frame(width: InputPanelController.width)
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
