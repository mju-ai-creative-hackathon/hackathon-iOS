import SwiftUI
import AVFoundation

/// 마이 탭 "내가 만든 V-log" 섹션 (가로 스크롤 썸네일 + 전체 보기 그리드)
struct MyVlogSection: View {
    var onOpenPost: (CommunityPost) -> Void
    @Environment(CommunityStore.self) private var community
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                MyVlogAllView(onOpenPost: onOpenPost)
            } label: {
                HStack {
                    Text("내가 만든 V-log")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.gray)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if community.myPosts.isEmpty {
                VStack(spacing: 12) {
                    Text("아직 만든 V-log가 없어요")
                        .font(Theme.body)
                        .foregroundStyle(Theme.gray)
                    Button { store.selectedTab = .create } label: {
                        Text("숏폼 만들기")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.paper)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Theme.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(community.myPosts) { post in
                            Button { onOpenPost(post) } label: {
                                MyVlogThumb(post: post)
                                    .frame(width: 96, height: 136)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// 전체 보기 — 2열 그리드
struct MyVlogAllView: View {
    var onOpenPost: (CommunityPost) -> Void
    @Environment(CommunityStore.self) private var community

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if community.myPosts.isEmpty {
                Text("아직 만든 V-log가 없어요")
                    .font(Theme.body)
                    .foregroundStyle(Theme.gray)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(community.myPosts) { post in
                        Button { onOpenPost(post) } label: {
                            MyVlogThumb(post: post, large: true)
                                .aspectRatio(96.0 / 136.0, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("내가 만든 V-log")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 영상 길이 캐시 (media id → 초)
@MainActor
private enum MyVlogDurationCache {
    static var values: [UUID: Double] = [:]
}

private struct MyVlogThumb: View {
    let post: CommunityPost
    var large = false
    @State private var duration: Double?

    private var video: CommunityMedia? { post.media.first(where: \.isVideo) }
    private var coverURL: URL? {
        APIClient.shared.absolute(post.thumbnailUrl ?? post.media.first(where: { !$0.isVideo })?.url)
    }

    var body: some View {
        Color.black.opacity(0.08)
            .overlay { CachedImage(url: coverURL) }
            .overlay {
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: large ? 40 : 30, height: large ? 40 : 30)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: large ? 15 : 12))
                            .foregroundStyle(.white)
                    }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration {
                    Text(MyVlogThumb.format(duration))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .task(id: video?.id) { await loadDuration() }
    }

    private func loadDuration() async {
        guard let video else { duration = nil; return }
        if let d = MyVlogDurationCache.values[video.id] { duration = d; return }
        guard let url = APIClient.shared.absolute(video.url) else { return }
        guard let time = try? await AVURLAsset(url: url).load(.duration) else { return }
        let secs = time.seconds
        guard secs.isFinite, secs > 0 else { return }
        MyVlogDurationCache.values[video.id] = secs
        duration = secs
    }

    static func format(_ secs: Double) -> String {
        let total = Int(secs.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
