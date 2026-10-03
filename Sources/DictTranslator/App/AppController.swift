import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
final class AppController: NSObject, NSMenuDelegate {
    static let shared = AppController()

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?

    func start() {
        SettingsKeys.registerDefaults()
        setupStatusItem()
        setupHotkeys()
        SelectionController.shared.start()

        if !Permissions.isAccessibilityTrusted || !UserDefaults.standard.bool(forKey: SettingsKeys.onboardingShown) {
            showSettings(tab: .permissions)
            UserDefaults.standard.set(true, forKey: SettingsKeys.onboardingShown)
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "中日英辞典")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let input = NSMenuItem(title: "输入翻译", action: #selector(openInput), keyEquivalent: "")
        input.setShortcut(for: .openInput)
        input.target = self
        menu.addItem(input)

        let shot = NSMenuItem(title: "截图翻译", action: #selector(screenshot), keyEquivalent: "")
        shot.setShortcut(for: .screenshot)
        shot.target = self
        menu.addItem(shot)

        let sel = NSMenuItem(title: "翻译选中文本", action: #selector(translateSelection), keyEquivalent: "")
        sel.setShortcut(for: .translateSelection)
        sel.target = self
        menu.addItem(sel)

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "划词翻译", action: #selector(toggleSelection), keyEquivalent: "")
        toggle.state = UserDefaults.standard.bool(forKey: SettingsKeys.selectionEnabled) ? .on : .off
        toggle.target = self
        menu.addItem(toggle)

        if !Permissions.isAccessibilityTrusted {
            let warn = NSMenuItem(title: "⚠️ 未授权辅助功能（划词不可用）…", action: #selector(openPermissions), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openInput() { InputPanelController.shared.show() }
    @objc private func screenshot() { startScreenshot() }
    @objc private func translateSelection() { SelectionController.shared.translateCurrentSelection() }
    @objc private func openSettings() { showSettings(tab: .general) }
    @objc private func openPermissions() { showSettings(tab: .permissions) }

    @objc private func toggleSelection() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: SettingsKeys.selectionEnabled), forKey: SettingsKeys.selectionEnabled)
    }

    func startScreenshot() {
        // 菜单关闭动画结束后再开始截图
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenshotController.shared.start()
        }
    }

    // MARK: - 快捷键

    private func setupHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .openInput) {
            Task { @MainActor in InputPanelController.shared.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .screenshot) {
            Task { @MainActor in ScreenshotController.shared.start() }
        }
        KeyboardShortcuts.onKeyUp(for: .translateSelection) {
            Task { @MainActor in SelectionController.shared.translateCurrentSelection() }
        }
    }

    // MARK: - 设置窗口

    func showSettings(tab: SettingsTab) {
        SettingsState.shared.tab = tab
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(state: SettingsState.shared))
            let w = NSWindow(contentViewController: controller)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.title = "中日英辞典 设置"
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        guard let w = settingsWindow else { return }
        if !w.isVisible { w.center() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        startPermissionPolling()
    }

    /// 授权后自动刷新界面（AXIsProcessTrusted 状态变化没有通知）
    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                SettingsState.shared.refreshPermissions()
                if self.settingsWindow?.isVisible != true {
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }
}
