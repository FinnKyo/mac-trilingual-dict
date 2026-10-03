import AVFoundation

@MainActor
final class AudioPlayer {
    static let shared = AudioPlayer()
    private var player: AVPlayer?

    func play(_ url: URL?) {
        guard let url else { return }
        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.play()
    }
}
