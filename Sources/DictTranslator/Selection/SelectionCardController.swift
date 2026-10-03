import AppKit
import SwiftUI

/// 划词翻译结果卡片（不抢占前台 App 的焦点）
@MainActor
final class SelectionCardController: NSObject, ObservableObject {
    let vm = LookupViewModel()
    @Published var pinned = false

    static let width: CGFloat = 420
    private var width: CGFloat { Self.width }
    /// 卡片顶部工具栏 + 内边距的高度
    private let chromeHeight: CGFloat = 36
    private let preferredResultHeight: CGFloat = 520
    /// 结果区最大高度，随可用空间变化，保证卡片不超出屏幕
    @Published private(set) var resultMaxHeight: CGFloat = 460

    private lazy var panel: FloatingPanel = makePanel()

    private enum Placement {
        case below(top: CGFloat)       // 在选区下方，顶边固定
        case above(bottom: CGFloat)    // 在选区上方，底边固定
        case overlay(top: CGFloat)     // 上下空间都不够：贴着屏幕放置，可以盖住选区
    }
    private var placement: Placement = .below(top: 0)
    private var visibleFrame: NSRect = .zero
    private var availableHeight: CGFloat = 400

    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(size: NSSize(width: width, height: 100))
        p.onCancel = { [weak self] in self?.hide() }
        let hosting = NSHostingView(rootView: SelectionCardView(controller: self, vm: vm))
        hosting.sizingOptions = []
        p.contentView = hosting
        return p
    }

    func show(text: String, near anchor: NSRect) {
        pinned = false
        let screen = NSScreen.screen(containing: NSPoint(x: anchor.midX, y: anchor.midY))
        let vf = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)).insetBy(dx: 4, dy: 4)
        visibleFrame = vf
        let x = min(max(anchor.minX - 16, vf.minX), vf.maxX - width)

        let desired = chromeHeight + preferredResultHeight
        let spaceBelow = anchor.minY - 4 - vf.minY
        let spaceAbove = vf.maxY - (anchor.maxY + 4)
        let minUseful: CGFloat = 320
        if spaceBelow >= desired || (spaceBelow >= spaceAbove && spaceBelow >= minUseful) {
            placement = .below(top: anchor.minY - 4)
            availableHeight = spaceBelow
        } else if spaceAbove >= minUseful {
            placement = .above(bottom: anchor.maxY + 4)
            availableHeight = spaceAbove
        } else {
            placement = .overlay(top: min(anchor.minY - 4 + desired / 2, vf.maxY))
            availableHeight = vf.height
        }
        availableHeight = min(availableHeight, desired)
        resultMaxHeight = max(100, availableHeight - chromeHeight)

        let h = min(panel.frame.height, availableHeight)
        panel.setFrame(frameFor(height: h, x: x), display: false)
        vm.lookup(text)
        panel.orderFrontRegardless()
    }

    private func frameFor(height h: CGFloat, x: CGFloat) -> NSRect {
        var y: CGFloat
        switch placement {
        case .below(let top): y = top - h
        case .above(let bottom): y = bottom
        case .overlay(let top): y = top - h
        }
        // 最后保证完全落在屏幕可见范围内
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - h)
        return NSRect(x: x, y: y, width: width, height: h)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        vm.cancel()
    }

    func hideIfNotPinned() {
        if !pinned { hide() }
    }

    func updateHeight(_ contentHeight: CGFloat) {
        let h = ceil(min(max(contentHeight, 60), availableHeight))
        let frame = frameFor(height: h, x: panel.frame.minX)
        guard abs(panel.frame.height - frame.height) > 0.5 || abs(panel.frame.minY - frame.minY) > 0.5 else { return }
        panel.setFrame(frame, display: true, animate: false)
    }

    func openInMainWindow() {
        let t = vm.text
        hide()
        // 在卡片里手动切换过语言的，带到输入窗
        InputPanelController.shared.show(text: t, forcedLang: vm.forcedSourceLang)
    }
}

struct SelectionCardView: View {
    @ObservedObject var controller: SelectionCardController
    @ObservedObject var vm: LookupViewModel
    @State private var resultHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                WindowDragArea().frame(maxWidth: .infinity).frame(height: 20)
                IconButton(systemName: "arrow.up.left.and.arrow.down.right", help: "在输入窗中打开") {
                    controller.openInMainWindow()
                }
                IconButton(systemName: controller.pinned ? "pin.fill" : "pin", help: controller.pinned ? "取消固定" : "固定（点击别处不关闭）") {
                    controller.pinned.toggle()
                }
                IconButton(systemName: "xmark", help: "关闭 (Esc)") { controller.hide() }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            ScrollView {
                ResultView(vm: vm, showSource: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
                    .reportHeight { resultHeight = $0 }
            }
            .frame(height: min(resultHeight, controller.resultMaxHeight))
        }
        .frame(width: SelectionCardController.width)
        .background(Theme.panelTint)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.rule))
        .fixedSize(horizontal: false, vertical: true)
        .reportHeight { controller.updateHeight($0) }
    }
}
