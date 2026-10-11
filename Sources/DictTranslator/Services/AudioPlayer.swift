import AVFoundation

@MainActor
final class AudioPlayer {
    static let shared = AudioPlayer()
    private var player: AVPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    /// 每次播放请求的序号：MOJi 发音需要先请求地址，期间又点了别的就以最后一次为准
    private var requestId = 0

    func play(_ source: PronunciationSource) {
        requestId += 1
        stop()
        switch source {
        case .url(let url):
            play(url)
        case .speech(let text, let language):
            speak(text, language: language)
        case .moji(let id, let type, let text):
            let current = requestId
            Task { @MainActor in
                let url = try? await MojiDictService.audioURL(id: id, type: type)
                guard current == self.requestId else { return }
                // 取不到真人发音时用系统语音
                if let url { self.play(url) } else { self.speak(text, language: "ja-JP") }
            }
        }
    }

    private func play(_ url: URL?) {
        guard let url else { return }
        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.play()
    }

    private func speak(_ text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }

    private func stop() {
        player?.pause()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}
