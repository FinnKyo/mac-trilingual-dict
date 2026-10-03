import AppKit
import SwiftUI

/// 无边框浮动面板（圆角毛玻璃背景由 SwiftUI 内容绘制）
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// 浮窗不抢前台 App 的焦点，所以点击时它通常还不是 key window，AppKit 会把这第一次点击
    /// 只用来激活窗口、不传给内容（滚动区里的内容尤其如此）。这里先让窗口成为 key，再把同一次点击交给内容，
    /// 这样点一下就能直接点中按钮或输入框
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}

/// 浮窗不是 key window 时，第一次点击也要直接传给内容（否则要先点一下激活窗口，再点一次才生效）
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 可拖动窗口的区域
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 毛玻璃背景
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 报告内容高度，用于让面板高度自适应
struct HeightReporter: ViewModifier {
    let onChange: (CGFloat) -> Void
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onChange(geo.size.height) }
                    .onChange(of: geo.size.height) { _, h in onChange(h) }
            }
        )
    }
}

extension View {
    func reportHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(HeightReporter(onChange: onChange))
    }
}

extension NSScreen {
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}
