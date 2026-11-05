import SwiftUI

/// 인스타 릴스 스타일 전체화면 세로 페이징 피드
struct ReelsView: View {
    @Environment(AppStore.self) private var store
    @State private var currentID: Reel.ID?
    @State private var isMuted = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.reels) { reel in
                            ReelCellView(reel: reel,
                                         isActive: currentID == reel.id,
                                         isMuted: $isMuted,
                                         topInset: proxy.safeAreaInsets.top)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(reel.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
                .defaultScrollAnchor(.top)

                topBar
                    .padding(.top, proxy.safeAreaInsets.top + 6)
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
        .onAppear { if currentID == nil { currentID = store.reels.first?.id } }
        .onChange(of: store.reels.first?.id) { _, new in
            // 새 릴스가 게시되면 맨 앞으로
            if let new { currentID = new }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("릴스")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            Spacer()
            Button { store.isCreatingReel = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
                    Text("릴스 만들기").font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Theme.blue))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            Button { store.isCreatingReel = true } label: {
                Image(systemName: "camera")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            }
        }
        .padding(.horizontal, 16)
    }
}
