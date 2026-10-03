import AppKit
import ApplicationServices
import os

let selectionLog = Logger(subsystem: "com.finn.DictTranslator", category: "selection")

/// 读取当前前台 App 中选中的文本
///
/// 依次尝试：
/// 1. 鼠标位置下的元素（及其父元素）的选中文本 —— 网页、聊天记录等不可编辑区域的选区在这里
/// 2. 键盘焦点元素的选中文本 —— 输入框、文本编辑器
/// 3. 模拟 ⌘C（仅当 App 的「拷贝」菜单可用时，避免无选区时发出提示音），读取后恢复剪贴板
@MainActor
enum SelectedTextReader {
    static func read(mouseLocation: NSPoint? = nil, allowCopyFallback: Bool = true) async -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let name = app.bundleIdentifier ?? app.localizedName ?? "?"

        if let s = readViaAccessibility(mouseLocation: mouseLocation) {
            selectionLog.notice("[\(name, privacy: .public)] AX ok, \(s.count) chars")
            return s
        }

        // Chromium / Electron 默认不暴露辅助功能树，打开后重试一次
        if enableManualAccessibility(pid: pid) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let s = readViaAccessibility(mouseLocation: mouseLocation) {
                selectionLog.notice("[\(name, privacy: .public)] AX ok after enabling manual AX")
                return s
            }
        }

        guard allowCopyFallback else { return nil }
        if copyMenuItemEnabled(pid: pid) == false {
            selectionLog.notice("[\(name, privacy: .public)] copy menu disabled, no selection")
            return nil
        }
        let s = await readViaCopy()
        selectionLog.notice("[\(name, privacy: .public)] ⌘C fallback -> \(s?.count ?? -1) chars")
        return s
    }

    // MARK: - Accessibility

    static func readViaAccessibility(mouseLocation: NSPoint?) -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)

        if let p = mouseLocation {
            // AX 坐标原点在主屏左上角
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            var element: AXUIElement?
            if AXUIElementCopyElementAtPosition(system, Float(p.x), Float(primaryHeight - p.y), &element) == .success,
               var current = element {
                for _ in 0..<8 {
                    if let s = selectedText(of: current) { return s }
                    guard let parent: AXUIElement = attribute(current, kAXParentAttribute) else { break }
                    current = parent
                }
            }
        }

        if let focused: AXUIElement = attribute(system, kAXFocusedUIElementAttribute),
           let s = selectedText(of: focused) {
            return s
        }
        return nil
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        if let s: String = attribute(element, kAXSelectedTextAttribute) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        // WebKit / Chromium 的网页区域：通过文本标记范围读取选区
        var range: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &range) == .success,
              let r = range else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, r, &value) == .success,
              let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if T.self == AXUIElement.self {
            guard let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
            return (v as! AXUIElement) as? T
        }
        return value as? T
    }

    private static var manualAXEnabledPIDs = Set<pid_t>()

    private static func enableManualAccessibility(pid: pid_t) -> Bool {
        guard !manualAXEnabledPIDs.contains(pid) else { return false }
        manualAXEnabledPIDs.insert(pid)
        let appEl = AXUIElementCreateApplication(pid)
        return AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
    }

    /// 查找 App 菜单栏中快捷键为 ⌘C 的菜单项，返回其是否可用；找不到时返回 nil
    static func copyMenuItemEnabled(pid: pid_t) -> Bool? {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        guard let menuBar: AXUIElement = attribute(appEl, kAXMenuBarAttribute) else { return nil }
        let topItems: [AXUIElement] = attribute(menuBar, kAXChildrenAttribute) ?? []
        // 「编辑」菜单通常在第 2~4 个，但不同语言名字不同，因此全部遍历
        for top in topItems {
            let menus: [AXUIElement] = attribute(top, kAXChildrenAttribute) ?? []
            for menu in menus {
                let items: [AXUIElement] = attribute(menu, kAXChildrenAttribute) ?? []
                for item in items {
                    guard let ch: String = attribute(item, kAXMenuItemCmdCharAttribute), ch.uppercased() == "C" else { continue }
                    let mods: Int = attribute(item, kAXMenuItemCmdModifiersAttribute) ?? 0
                    guard mods == 0 else { continue }   // 0 表示仅 ⌘
                    return attribute(item, kAXEnabledAttribute) ?? true
                }
            }
        }
        return nil
    }

    // MARK: - ⌘C

    /// 模拟 ⌘C 读取选中文本，读取后恢复剪贴板原内容
    static func readViaCopy() async -> String? {
        let pb = NSPasteboard.general
        let oldChange = pb.changeCount
        let saved = savePasteboard(pb)

        postCommandC()

        var result: String?
        for _ in 0..<16 {   // 最多等 ~400ms
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pb.changeCount != oldChange {
                // 部分 App 先清空再写入，稍等写完
                try? await Task.sleep(nanoseconds: 20_000_000)
                result = pb.string(forType: .string)
                break
            }
        }
        if pb.changeCount != oldChange {
            restorePasteboard(pb, items: saved)
        }
        let trimmed = result?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private static func postCommandC() {
        // 完整模拟「按下 ⌘ → 按下 C → 松开 C → 松开 ⌘」，部分 App 只认带修饰键按下事件的组合
        let src = CGEventSource(stateID: .hidSystemState)
        let cmd: CGKeyCode = 0x37, keyC: CGKeyCode = 0x08
        let events: [(CGKeyCode, Bool)] = [(cmd, true), (keyC, true), (keyC, false), (cmd, false)]
        for (key, down) in events {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.flags = (key == cmd && !down) ? [] : .maskCommand
            e.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private static func savePasteboard(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private static func restorePasteboard(_ pb: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let newItems: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(newItems)
    }
}
