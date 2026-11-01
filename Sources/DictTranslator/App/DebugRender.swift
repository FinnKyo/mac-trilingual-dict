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
        if let i = args.firstIndex(of: "--word-bench"), args.count > i + 2 { return runWordBench(input: args[i + 1], output: args[i + 2]) }
        if let i = args.firstIndex(of: "--mt-bench"), args.count > i + 4 {
            return runTranslationBench(input: args[i + 1], from: args[i + 2], to: args[i + 3], output: args[i + 4],
                                       limit: args.count > i + 5 ? Int(args[i + 5]) ?? 100 : 100)
        }
        if let i = args.firstIndex(of: "--furigana") {
            // 每行一句，输出「表层(读音)[原形]」，检查注音用
            for text in args[(i + 1)...] {
                let words = FuriganaService.tokens(for: text).map { t in
                    t.surface + (t.reading.map { "(\($0))" } ?? "") + (t.lemma.map { "[\($0)]" } ?? "")
                }
                print(words.joined(separator: " "))
            }
            exit(0)
        }
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
                if !vm.isLoading { break }
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

    /// DictTranslator --mt-bench <原文.txt> <zh|en|ja> <zh|en|ja> <译文.txt> [句数]：每行一句，逐句用当前翻译设置翻译，
    /// 输出与原文逐行对应（评分见 scripts/chrf.py）
    private static func runTranslationBench(input: String, from: String, to: String, output: String, limit: Int) -> Bool {
        guard let text = try? String(contentsOfFile: input, encoding: .utf8), let f = Lang(rawValue: from), let t = Lang(rawValue: to) else {
            print("参数错误"); exit(1)
        }
        SettingsKeys.registerDefaults()
        let lines = Array(text.components(separatedBy: "\n").filter { !$0.isEmpty }.prefix(limit))
        Task { @MainActor in
            var out: [String] = []
            for (n, line) in lines.enumerated() {
                // 「⏎」表示原文里的换行（模拟从 PDF 复制的折行文本）
                let source = line.replacingOccurrences(of: "⏎", with: "\n")
                let r = (try? await MachineTranslator.translate(source, from: f, to: t))?.text ?? ""
                out.append(r.replacingOccurrences(of: "\n", with: " "))
                if (n + 1) % 20 == 0 { print("\(n + 1)/\(lines.count)") }
            }
            try? (out.joined(separator: "\n") + "\n").write(toFile: output, atomically: true, encoding: .utf8)
            print("\(out.filter(\.isEmpty).count) 句失败 -> \(output)")
            exit(0)
        }
        return true
    }

    /// DictTranslator --word-bench <词表.json> <结果.json>：词表为 {"中文词": ["可接受的日语", ...]}，
    /// 输出界面上中文词的日语卡片会显示的内容：机器翻译、MOJi 候选
    private static func runWordBench(input: String, output: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: input),
              let gold = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            print("无法读取词表 \(input)"); exit(1)
        }
        SettingsKeys.registerDefaults()
        Task { @MainActor in
            var rows: [[String: Any]] = []
            for word in gold.keys.sorted() {
                let mt = (try? await MachineTranslator.translate(word, from: .zh, to: .ja))?.text ?? ""
                let entry = (try? await MojiDictService.chineseToJapanese(word)) ?? nil
                let candidates = entry?.candidates ?? []
                let falseFriend = FalseFriendDetector.falseFriend(word, translation: mt, candidates: candidates,
                                                                  equivalents: entry?.equivalents ?? [])
                rows.append(["word": word, "mt": mt,
                             "falseFriend": falseFriend.map { "\($0.spell)（\($0.reading ?? "")）\($0.excerpt)" } ?? "",
                             "equivalents": (entry?.equivalents ?? []).prefix(3).map(\.spell),
                             "moji": candidates.prefix(6).map { ["spell": $0.spell, "reading": $0.reading ?? "", "excerpt": $0.excerpt] }])
            }
            let json = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            FileManager.default.createFile(atPath: output, contents: json)
            print("\(rows.count) 词 -> \(output)")
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
        } else if cmd.hasPrefix("ocr:") {
            ScreenshotController.shared.debugRecognize(file: String(cmd.dropFirst(4)))
        } else if cmd.hasPrefix("shot:") {
            InputPanelController.shared.debugShot(String(cmd.dropFirst(5)))
        } else if cmd.hasPrefix("appearance:") {
            NSApp.appearance = NSAppearance(named: cmd.hasSuffix("dark") ? .darkAqua : .aqua)
        } else if cmd.hasPrefix("inputcmd:") {
            InputPanelController.shared.debugCommand(String(cmd.dropFirst(9)))
        } else if cmd.hasPrefix("pasteboard:") {
            Pasteboard.copy(String(cmd.dropFirst(11)))
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
        } else if cmd == "click" || cmd == "move" {
            // 在当前光标位置模拟一次左键点击 / 鼠标移动（光标可用 CGWarpMouseCursorPosition 移动，无需辅助功能权限；
            // 瞬移光标不会产生移动事件，窗口内的悬停状态要靠 move 更新）
            let p = NSEvent.mouseLocation
            guard let w = NSApp.window(withWindowNumber: NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0)) else { return }
            let local = w.convertPoint(fromScreen: p)
            let types: [NSEvent.EventType] = cmd == "move" ? [.mouseMoved] : [.leftMouseDown, .leftMouseUp]
            for type in types {
                if let e = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    w.sendEvent(e)
                }
            }
        } else if cmd == "settings" {
            AppController.shared.showSettings(tab: .general)
        } else if cmd == "hide" {
            InputPanelController.shared.pinned = false
            InputPanelController.shared.close()
        }
    }
}
#endif
