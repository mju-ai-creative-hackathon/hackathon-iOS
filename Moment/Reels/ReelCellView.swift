import SwiftUI

/// 릴스 한 장(전체화면)
struct ReelCellView: View {
    @Environment(AppStore.self) private var store
    let reel: Reel
    let isActive: Bool
    @Binding var isMuted: Bool
    var topInset: CGFloat = 0

    @State private var looping: LoopingPlayer?
    @State private var heartBurst = false
    @State private var heartPos: CGPoint = .zero
    @State private var showSpeaker = false
    @State private var captionExpanded = false
    @State private var albumSpin = false

    var body: some View {
        ZStack {
            media
            // 하단 그라데이션
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 340)
            }
            .allowsHitTesting(false)

            if heartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8)
                    .position(heartPos)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if case .remoteVideo = reel.content, showSpeaker {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .padding(22)
                    .background(Circle().fill(.black.opacity(0.5)))
                    .transition(.opacity.combined(with: .scale))
                    .allowsHitTesting(false)
            }

            HStack(alignment: .bottom, spacing: 0) {
                infoColumn
                actionColumn
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(Color.black)
        .clipped()
        .onAppear { setupPlayer() }
        .onChange(of: isActive) { _, _ in syncPlayback() }
        .onChange(of: isMuted) { _, m in looping?.player.isMuted = m }
        .onDisappear { looping?.pause() }
    }

    // MARK: media
    @ViewBuilder private var media: some View {
        GeometryReader { geo in
            Group {
                switch reel.content {
                case .remoteVideo:
                    if let looping { PlayerLayerView(player: looping.player) } else { Color.black }
                case .slideshow(let images):
                    SlideshowReelView(images: images, isPlaying: isActive)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2).onEnded { v in doubleTap(at: v.location) }
                    .exclusively(before: SpatialTapGesture(count: 1).onEnded { _ in singleTap() })
            )
        }
    }

    private func setupPlayer() {
        if case .remoteVideo(let url) = reel.content, looping == nil {
            let p = LoopingPlayer(url: url)
            p.player.isMuted = isMuted
            looping = p
        }
        syncPlayback()
    }

    private func syncPlayback() {
        if isActive { looping?.play() } else { looping?.pause() }
    }

    private func singleTap() {
        guard case .remoteVideo = reel.content else { return }
        isMuted.toggle()
        withAnimation(.easeOut(duration: 0.15)) { showSpeaker = true }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeIn(duration: 0.25)) { showSpeaker = false }
        }
    }

    private func doubleTap(at p: CGPoint) {
        if !reel.isLiked { store.toggleLike(reel.id) }
        heartPos = p
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) { heartBurst = true }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeIn(duration: 0.2)) { heartBurst = false }
        }
    }

    // MARK: 오른쪽 액션
    private var actionColumn: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            actionButton(symbol: reel.isLiked ? "heart.fill" : "heart",
                         label: Self.format(reel.likeCount),
                         tint: reel.isLiked ? Theme.red : .white) { store.toggleLike(reel.id) }
            actionButton(symbol: "bubble.right", label: Self.format(reel.commentCount)) {}
            actionButton(symbol: "paperplane", label: nil) {}
            actionButton(symbol: reel.isSaved ? "bookmark.fill" : "bookmark", label: nil) { store.toggleSave(reel.id) }
            actionButton(symbol: "ellipsis", label: nil) {}
            album
        }
        .frame(width: 52)
    }

    private func actionButton(symbol: String, label: String?, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                if let label {
                    Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var album: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Theme.blue, Theme.blueSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 32, height: 32)
            .overlay(Image(systemName: "music.note").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white, lineWidth: 2))
            .rotationEffect(.degrees(albumSpin ? 360 : 0))
            .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: albumSpin)
            .onAppear { albumSpin = true }
            .shadow(color: .black.opacity(0.4), radius: 3)
    }

    // MARK: 하단 정보
    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let course = reel.tourCourseTitle {
                Text("🏁 도장깨기 · \(course)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.blue))
            }

            HStack(spacing: 8) {
                AvatarView(url: reel.author.avatarURL, size: 34)
                Text(reel.author.username)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                if reel.isMine {
                    Text("내 릴스")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.blue))
                } else {
                    Text("팔로우")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                }
            }

            Text(reel.caption)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .lineLimit(captionExpanded ? nil : 2)
                .multilineTextAlignment(.leading)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { captionExpanded.toggle() } }

            HStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 12, weight: .semibold))
                MarqueeText(text: reel.musicTitle, font: .system(size: 13, weight: .medium))
                    .frame(maxWidth: 200)
            }
            .foregroundStyle(.white)

            if let loc = reel.location {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .semibold))
                    Text(loc).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.22)))
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
    }

    static func format(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000 { return String(format: "%.1f천", Double(n) / 1_000) }
        return "\(n)"
    }
}
