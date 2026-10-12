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
        setupMainMenu()
        setupStatusItem()
        setupHotkeys()
        SelectionController.shared.start()

        if !Permissions.isAccessibilityTrusted || !UserDefaults.standard.bool(forKey: SettingsKeys.onboardingShown) {
            showSettings(tab: .permissions)
            UserDefaults.standard.set(true, forKey: SettingsKeys.onboardingShown)
        }
    }

    // MARK: - 主菜单

    /// 菜单栏 App 没有主菜单时，输入框里的 ⌘C ⌘V ⌘X ⌘A ⌘Z 都不会生效（这些快捷键由主菜单的「编辑」菜单分发）。
    /// 菜单栏上看不到它，但快捷键需要它
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "隐藏", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
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
        @discardableResult
        func add(_ title: String, _ action: Selector, key: String = "", shortcut: KeyboardShortcuts.Name? = nil) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            if let shortcut { item.setShortcut(for: shortcut) }
            return item
        }

        add("输入翻译", #selector(openInput), shortcut: .openInput)
        add("截图翻译", #selector(screenshot), shortcut: .screenshot)
        add("翻译选中文本", #selector(translateSelection), shortcut: .translateSelection)
        menu.addItem(.separator())
        add("划词翻译", #selector(toggleSelection)).state = UserDefaults.standard.bool(forKey: SettingsKeys.selectionEnabled) ? .on : .off
        if !Permissions.isAccessibilityTrusted {
            add("⚠️ 未授权辅助功能（划词不可用）…", #selector(openPermissions))
        }
        menu.addItem(.separator())
        add("设置…", #selector(openSettings), key: ",")
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
