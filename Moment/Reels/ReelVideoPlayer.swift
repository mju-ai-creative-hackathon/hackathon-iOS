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

/// 첫 프레임이 실제로 그려질 준비가 되면(isReadyForDisplay) 알려주는 투명 배경 플레이어 레이어.
/// 썸네일 위에 미리 깔아두고 준비된 뒤에만 보이게 해 검은 화면 깜빡임을 없앤다.
struct ReadyPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onReady: (Bool) -> Void

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView()
        v.backgroundColor = .clear
        v.playerLayer.backgroundColor = UIColor.clear.cgColor
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        context.coordinator.observe(v.playerLayer, onReady: onReady)
        return v
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: NSKeyValueObservation?
        func observe(_ layer: AVPlayerLayer, onReady: @escaping (Bool) -> Void) {
            token = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { l, _ in
                let ready = l.isReadyForDisplay
                DispatchQueue.main.async { onReady(ready) }
            }
        }
    }
}
