import AppKit
import SwiftUI

#if DEBUG
/// 开发调试用：DictTranslator --render <文本> <输出.png> [zh|en|ja]
/// 离屏渲染查询结果，便于检查界面排版
@MainActor
enum DebugRender {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--identify"), args.count > i + 1 { return runIdentify(corpus: args[i + 1]) }
        guard let i = args.firstIndex(of: "--render"), args.count > i + 2 else { return false }
        let text = args[i + 1]
        let out = URL(fileURLWithPath: args[i + 2])
        let forced = args.count > i + 3 ? Lang(rawValue: args[i + 3]) : nil  // --dark 可放在任意位置
        SettingsKeys.registerDefaults()
        NSApp.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)

        let vm = LookupViewModel()
        vm.lookup(text, forcedLang: forced)
        Task { @MainActor in
            // 等待网络结果
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !isLoading(vm) { break }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            let view = ResultView(vm: vm, showSource: true)
                .padding(12)
                .frame(width: 440)
                .background(Theme.panelTint)
                .background(Color(nsColor: .windowBackgroundColor))
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 10)
            let size = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out)
            }
            print("rendered \(Int(size.width))x\(Int(size.height)) -> \(out.path)")
            exit(0)
        }
        return true
    }

    /// DictTranslator --identify <语料.json>：语料为 {"ja": [...], "zh": [...]}，输出中日识别的准确率和错例
    private static func runIdentify(corpus path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            print("无法读取语料 \(path)"); exit(1)
        }
        Task { @MainActor in
            for (label, expected) in [("ja", Lang.ja), ("zh", Lang.zh)] {
                let items = obj[label] ?? []
                var wrong: [String] = [], viaScript = 0
                for t in items {
                    let r = await LanguageIdentifier.identify(t)
                    if r.trace == ["script"] { viaScript += 1 }
                    if r.lang != expected { wrong.append("\(t) \(r.trace.joined(separator: ","))") }
                }
                print("\(label): \(items.count - wrong.count)/\(items.count) 正确（文字构成直接判定 \(viaScript)）")
                wrong.forEach { print("  ✗ \($0)") }
            }
            exit(0)
        }
        return true
    }

    private static func isLoading(_ vm: LookupViewModel) -> Bool {
        vm.isDetecting || vm.englishEntry.isLoading || vm.japaneseEntry.isLoading || vm.chineseEnglish.isLoading
            || vm.chineseJapanese.isLoading || vm.translations.values.contains { $0.isLoading }
    }
}

/// 仅调试版：通过分布式通知驱动界面并截取本 App 自己的窗口
/// 例：发送 name "dict.debug"，object "input:run" / "select:700,500:食べる" / "snap:/tmp/x" / "settings" / "hide"
@MainActor
enum DebugCommands {
    static func install() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("dict.debug"), object: nil, queue: .main) { note in
            guard let cmd = note.object as? String else { return }
            MainActor.assumeIsolated { handle(cmd) }
        }
    }

    private static func handle(_ cmd: String) {
        if cmd.hasPrefix("input:") {
            InputPanelController.shared.pinned = true
            InputPanelController.shared.show(text: String(cmd.dropFirst(6)))
        } else if cmd == "hotkey" {
            // 模拟 ⌥A（不固定窗口）
            InputPanelController.shared.show()
        } else if cmd.hasPrefix("select:") {
            // select:x,y:文本  —— 在指定屏幕坐标模拟划词并触发小图标（打开输入窗）
            let parts = cmd.dropFirst(7).split(separator: ":", maxSplits: 1)
            let xy = parts[0].split(separator: ",").compactMap { Double($0) }
            SelectionController.shared.debugSelect(text: String(parts[1]), at: NSPoint(x: xy[0], y: xy[1]))
        } else if cmd.hasPrefix("icon:") {
            SelectionController.shared.debugShowIcon(text: String(cmd.dropFirst(5)), at: NSEvent.mouseLocation)
        } else if cmd.hasPrefix("inputtype:") {
            InputPanelController.shared.debugKey(String(cmd.dropFirst(10)))
        } else if cmd.hasPrefix("inputstate:") {
            try? InputPanelController.shared.debugState().write(toFile: String(cmd.dropFirst(11)), atomically: true, encoding: .utf8)
        } else if cmd.hasPrefix("snap:") {
            let base = String(cmd.dropFirst(5))
            var lines: [String] = []
            for (i, w) in NSApp.windows.enumerated() where w.isVisible {
                guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                let path = "\(base)_\(i).png"
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                lines.append("\(path) \(type(of: w)) frame=\(NSStringFromRect(w.frame)) key=\(w.isKeyWindow)")
            }
            if let screen = NSScreen.main { lines.append("screen=\(NSStringFromRect(screen.visibleFrame))") }
            try? lines.joined(separator: "\n").write(toFile: "\(base)_info.txt", atomically: true, encoding: .utf8)
        } else if cmd == "settings" {
            AppController.shared.showSettings(tab: .general)
        } else if cmd == "hide" {
            InputPanelController.shared.pinned = false
            InputPanelController.shared.close()
        }
    }
}
#endif
