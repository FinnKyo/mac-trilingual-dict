import AppKit

/// ⌥S 截图翻译：系统交互式截图 → Vision OCR → 翻译
@MainActor
final class ScreenshotController {
    static let shared = ScreenshotController()
    private var running = false

    func start() {
        guard !running else { return }
        guard Permissions.hasScreenRecording else {
            Permissions.requestScreenRecording()
            let alert = NSAlert()
            alert.messageText = "需要「屏幕录制」权限"
            alert.informativeText = "截图翻译需要屏幕录制权限。请在「系统设置 › 隐私与安全性 › 屏幕与系统音频录制」中勾选「中日英辞典」，然后重新打开本 App。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                Permissions.openScreenRecordingSettings()
            }
            return
        }
        running = true
        let wasVisible = InputPanelController.shared.isVisible
        if wasVisible, !InputPanelController.shared.pinned { InputPanelController.shared.close() }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dict-ocr-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i 交互选区（空格可切换窗口模式），-x 不播放声音，-o 窗口模式不带阴影
        process.arguments = ["-i", "-x", "-o", url.path]
        process.terminationHandler = { _ in
            Task { @MainActor in
                await self.finish(url: url)
            }
        }
        do {
            try process.run()
        } catch {
            running = false
            InputPanelController.shared.show(status: "无法启动截图：\(error.localizedDescription)")
        }
    }

    private func finish(url: URL) async {
        defer {
            running = false
            try? FileManager.default.removeItem(at: url)
        }
        // 用户按 Esc 取消时不会生成文件
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        InputPanelController.shared.vm.clear()
        InputPanelController.shared.show(status: "正在识别文字…")
        do {
            let text = try await OCRService.recognizeText(in: cg)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                InputPanelController.shared.show(status: "截图中没有识别到文字")
            } else {
                InputPanelController.shared.show(text: text, status: "截图识别结果（可编辑后回车重新翻译）")
            }
        } catch {
            InputPanelController.shared.show(status: "文字识别失败：\(error.localizedDescription)")
        }
    }
}
