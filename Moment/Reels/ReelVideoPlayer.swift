import SwiftUI
import AVFoundation

/// 루프 재생 플레이어 (AVQueuePlayer + AVPlayerLooper)
@MainActor
final class LoopingPlayer {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init(url: URL) {
        let q = AVQueuePlayer()
        q.isMuted = true
        q.actionAtItemEnd = .none
        self.looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
        self.player = q
    }

    func play() { player.play() }
    func pause() { player.pause() }
}

/// 컨트롤 없는 AVPlayerLayer 뷰 (resizeAspectFill)
final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}
