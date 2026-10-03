import AppKit
import SwiftUI

/// 划词翻译：松开鼠标后在选区旁显示小图标，鼠标移到图标上弹出翻译卡片
@MainActor
final class SelectionController: NSObject {
    static let shared = SelectionController()

    private var monitors: [Any] = []
    private var mouseDownLocation: NSPoint = .zero
    private var mouseDownTime: TimeInterval = 0
    private var pendingRead: Task<Void, Never>?
    private var hideIconWork: DispatchWorkItem?

    private var selectedText = ""
    private lazy var iconPanel: FloatingPanel = makeIconPanel()
    private lazy var card = SelectionCardController()

    func start() {
        guard monitors.isEmpty else { return }
        selectionLog.notice("selection monitor start, trusted=\(Permissions.isAccessibilityTrusted)")
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .scrollWheel, .keyDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            let clickCount = type == .leftMouseUp || type == .leftMouseDown ? event.clickCount : 0
            let keyCode = type == .keyDown ? event.keyCode : 0
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.handle(type: type, clickCount: clickCount, keyCode: keyCode, location: location)
            }
        }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hideIcon()
        card.hide()
    }

    private func handle(type: NSEvent.EventType, clickCount: Int, keyCode: UInt16, location: NSPoint) {
        switch type {
        case .leftMouseDown:
            mouseDownLocation = location
            mouseDownTime = ProcessInfo.processInfo.systemUptime
            pendingRead?.cancel()
            hideIcon()
            card.hideIfNotPinned()
        case .leftMouseUp:
            let dx = location.x - mouseDownLocation.x, dy = location.y - mouseDownLocation.y
            let dragged = (dx * dx + dy * dy) > 25
            let multiClick = clickCount >= 2
            guard dragged || multiClick else { return }
            selectionLog.notice("mouseUp dragged=\(dragged) clicks=\(clickCount)")
            scheduleRead(at: location)
        case .rightMouseDown, .scrollWheel:
            pendingRead?.cancel()
            hideIcon()
            if type == .rightMouseDown { card.hideIfNotPinned() }
        case .keyDown:
            pendingRead?.cancel()
            hideIcon()
            if keyCode == 53 { card.hide() }  // Esc
        default:
            break
        }
    }

    private func scheduleRead(at location: NSPoint) {
        pendingRead?.cancel()
        guard UserDefaults.standard.bool(forKey: SettingsKeys.selectionEnabled) else { return }
        guard Permissions.isAccessibilityTrusted else {
            selectionLog.notice("skip: accessibility not trusted")
            return
        }
        if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           SettingsKeys.blacklistedBundleIDs.contains(bid) || bid == Bundle.main.bundleIdentifier {
            selectionLog.notice("skip: blacklisted \(bid, privacy: .public)")
            return
        }
        pendingRead = Task { @MainActor [weak self] in
            // 等目标 App 完成选区更新
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            guard let text = await SelectedTextReader.read(mouseLocation: location), !Task.isCancelled else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 3000 else { return }
            // 纯数字/符号不翻译
            guard trimmed.unicodeScalars.contains(where: { LanguageDetector.isLatinLetter($0) || LanguageDetector.isCJKIdeograph($0) || LanguageDetector.isKana($0) }) else { return }
            self?.showIcon(for: trimmed, at: location)
        }
    }

    // MARK: - 图标

    private func makeIconPanel() -> FloatingPanel {
        let p = FloatingPanel(size: NSSize(width: 26, height: 26))
        p.hasShadow = true
        let view = HoverIconView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        view.onHover = { [weak self] in self?.iconActivated() }
        p.contentView = view
        return p
    }

    private func showIcon(for text: String, at mouse: NSPoint) {
        selectedText = text
        let size = iconPanel.frame.size
        var origin = NSPoint(x: mouse.x + 10, y: mouse.y - size.height - 10)
        if let vf = NSScreen.screen(containing: mouse)?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 2), vf.maxX - size.width - 2)
            if origin.y < vf.minY + 2 { origin.y = mouse.y + 12 }
            origin.y = min(origin.y, vf.maxY - size.height - 2)
        }
        iconPanel.setFrameOrigin(origin)
        iconPanel.alphaValue = 1
        iconPanel.orderFrontRegardless()

        hideIconWork?.cancel()
        let delay = max(1.5, UserDefaults.standard.double(forKey: SettingsKeys.iconDismissDelay))
        let work = DispatchWorkItem { [weak self] in self?.hideIcon() }
        hideIconWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hideIcon() {
        hideIconWork?.cancel()
        hideIconWork = nil
        if iconPanel.isVisible { iconPanel.orderOut(nil) }
    }

    private func iconActivated() {
        guard iconPanel.isVisible, !selectedText.isEmpty else { return }
        let anchor = iconPanel.frame
        hideIcon()
        card.show(text: selectedText, near: anchor)
    }

    #if DEBUG
    func debugShowIcon(text: String, at p: NSPoint) { showIcon(for: text, at: p) }
    func debugShowCard(text: String, at p: NSPoint) { showIcon(for: text, at: p); iconActivated() }
    func debugCard(_ action: (SelectionCardController) -> Void) { action(card) }
    #endif

    /// ⌥D：直接翻译当前选中文本
    func translateCurrentSelection() {
        Task { @MainActor in
            // 等用户松开快捷键的修饰键，避免模拟 ⌘C 时变成 ⌥⌘C
            for _ in 0..<20 where !NSEvent.modifierFlags.intersection([.option, .control, .shift]).isEmpty {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            guard Permissions.isAccessibilityTrusted else {
                Permissions.promptAccessibility()
                return
            }
            if let text = await SelectedTextReader.read() {
                InputPanelController.shared.show(text: text)
            } else {
                InputPanelController.shared.show(status: "没有读取到选中的文本，可直接输入")
            }
        }
    }
}

/// 划词后出现的小图标，鼠标移入即触发
final class HoverIconView: NSView {
    var onHover: (() -> Void)?
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = Theme.iconFill.cgColor
        let img = NSImageView(frame: bounds.insetBy(dx: 5, dy: 5))
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        img.image = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: "翻译")?
            .withSymbolConfiguration(config)
        img.contentTintColor = .white
        img.autoresizingMask = [.width, .height]
        addSubview(img)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onHover?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
