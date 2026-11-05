import SwiftUI
import AVKit

/// 커뮤니티 탭: 검색 + 인기 태그 + 랜덤 탐색 그리드
struct CommunityView: View {
    @Environment(CommunityStore.self) private var community
    @Environment(AppStore.self) private var store
    @State private var selected: CommunityPost?
    // 화면에서 재생되는 영상은 딱 하나: 누른 영상(pinned)이 보이는 동안 우선, 아니면 화면 가운데에 가장 가까운 영상
    @State private var frames: [UUID: CGRect] = [:]
    @State private var viewport: CGSize = .zero
    @State private var pinned: UUID?
    @State private var playing: UUID?
    @State private var settleTask: Task<Void, Never>?   // 스크롤 멈춤 감지(마지막 움직임 후 0.25초)
    @FocusState private var searching: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    var body: some View {
        @Bindable var community = community
        VStack(spacing: 0) {
            searchBar(text: $community.keyword).padding(.top, 10)
            tagChips
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(community.posts) { post in
                        GridCell(post: post, saved: community.saved.contains(post.id),
                                 isPlaying: selected == nil && playing == post.id,
                                 onSave: { community.toggleSaved(post.id) }, onTap: { selected = post },
                                 onPress: { pinned = post.id; updatePlaying() })
                            .background(GeometryReader { g in
                                Color.clear.preference(key: CellFrameKey.self, value: [post.id: g.frame(in: .named("grid"))])
                            })
                            .task { await community.loadMoreIfNeeded(current: post) }
                    }
                }
                .padding(.horizontal, 16)
                footer
            }
            .coordinateSpace(name: "grid")
            .background(GeometryReader { g in Color.clear.onAppear { viewport = g.size }.onChange(of: g.size) { _, v in viewport = v } })
            .onPreferenceChange(CellFrameKey.self) { f in
                // 셀 위치가 바뀜 = 스크롤 중 → 재생·고정 모두 취소, 멈추면 다시 고르기
                let moved = f.contains { id, r in frames[id].map { abs($0.minY - r.minY) > 0.5 } ?? false }
                frames = f
                if moved {
                    pinned = nil
                    if playing != nil { playing = nil }
                }
                settleTask?.cancel()
                settleTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    updatePlaying()
                }
            }
            .onChange(of: community.posts.map(\.id)) { _, ids in
                if let p = pinned, !ids.contains(p) { pinned = nil }
                updatePlaying()
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await community.reload() }
        }
        .background(Theme.bg)
        .task { if community.posts.isEmpty { await community.reload() } }
        .sheet(item: $selected) { post in
            PostDetailView(post: post) { tag in
                selected = nil
                Task { await community.select(tag: tag) }
            }
            .presentationDragIndicator(.visible)
        }
    }

    private func updatePlaying() {
        let view = CGRect(origin: .zero, size: viewport)
        let videoIds = Set(community.posts.filter { $0.media.first?.isVideo == true }.map(\.id))
        // 절반 이상 보이는 셀만 후보
        let visible = frames.filter { id, r in
            videoIds.contains(id) && r.intersection(view).height >= r.height * 0.5
        }
        if let p = pinned, visible[p] != nil {
            if playing != p { playing = p }
            return
        }
        if pinned != nil, visible[pinned!] == nil { pinned = nil }
        let center = CGPoint(x: view.midX, y: view.height * 0.42)
        let best = visible.min { a, b in
            hypot(a.value.midX - center.x, a.value.midY - center.y) < hypot(b.value.midX - center.x, b.value.midY - center.y)
        }?.key
        if playing != best { playing = best }
    }

    private var header: some View {
        HStack {
            Text("커뮤니티").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            Button { store.selectedTab = .create } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .heavy))
                    Text("숏폼 만들기").font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Capsule().fill(Theme.red))
            }
        }
        .padding(.horizontal, 16).frame(height: 52)
    }

    private func searchBar(text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.gray)
            TextField("보고 싶은 서울을 검색해 보세요", text: text)
                .focused($searching)
                .submitLabel(.search)
                .onSubmit { Task { await community.search() } }
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    Task { await community.search() }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.gray) }
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14).frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .padding(.horizontal, 16)
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("전체", on: community.selectedTag == nil) { Task { await community.select(tag: nil) } }
                ForEach(community.tags, id: \.tag) { t in
                    chip("#\(t.tag)", on: community.selectedTag == t.tag) { Task { await community.select(tag: t.tag) } }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: on ? .bold : .medium))
                .foregroundStyle(on ? .white : Theme.ink)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(on ? Theme.red : .white))
                .overlay(Capsule().strokeBorder(on ? .clear : Theme.red.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var footer: some View {
        if community.isLoading {
            ProgressView().tint(Theme.red).padding(.vertical, 24)
        } else if let error = community.errorMessage {
            VStack(spacing: 10) {
                Text(error).font(.system(size: 13)).foregroundStyle(Theme.gray)
                Button("다시 시도") { Task { await community.reload() } }
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.red)
            }
            .padding(.vertical, 40)
        } else if community.posts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30)).foregroundStyle(Theme.line)
                Text(community.keyword.isEmpty && community.selectedTag == nil
                     ? "아직 올라온 게시물이 없어요.\n첫 숏폼을 공유해 보세요!" : "검색 결과가 없어요.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13)).foregroundStyle(Theme.gray)
            }
            .padding(.vertical, 60)
        }
        Color.clear.frame(height: 20)
    }
}

// MARK: - 그리드 셀

private struct CellFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct GridCell: View {
    let post: CommunityPost
    var saved = false
    var isPlaying = false
    var onSave: () -> Void = {}
    var onTap: () -> Void = {}
    var onPress: () -> Void = {}
    @State private var player: LoopingPlayer?
    @State private var ready = false      // 레이어에 첫 프레임 표시 가능
    @State private var started = false    // 재생 시간이 실제로 흐르기 시작함

    var body: some View {
        Color(Theme.cream)
            .aspectRatio(0.74, contentMode: .fit)
            .overlay {
                ZStack {
                    AsyncImage(url: APIClient.shared.absolute(post.thumbnailUrl)) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure: Image(systemName: "photo").foregroundStyle(Theme.line)
                        default: Color.clear
                        }
                    }
                    // 누르고 있는 동안 썸네일 자리에서 영상 재생
                    // 레이어는 미리 깔아두고, 첫 프레임이 그려질 준비가 된 뒤에만 보이게 (검은 화면 방지)
                    if let player {
                        ReadyPlayerLayerView(player: player.player) { ready = $0 }
                            .opacity(isPlaying && ready && started ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("SHORTS").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(height: 17)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onSave) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.black.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .overlay {
                if !(isPlaying && ready && started), post.media.first?.isVideo == true {
                    Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.black.opacity(0.3)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("@\(post.author.name)").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    Text(post.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    if !post.tags.isEmpty {
                        Text(post.tags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // 탭 → 상세, 길게 누르기 → 이 영상을 재생(스크롤해도 화면에 있는 동안 유지). onTapGesture 를 먼저 둬야 스크롤이 안 막힘
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 12, perform: onPress)
            .sensoryFeedback(.impact(weight: .light), trigger: isPlaying) { _, new in new }
            .animation(.easeOut(duration: 0.2), value: isPlaying && ready && started)
            .onAppear { if isPlaying { startPreview() } }
            .onChange(of: isPlaying) { _, on in on ? startPreview() : stopPreview() }
            .onDisappear(perform: stopPreview)
    }

    private func startPreview() {
        guard let m = post.media.first(where: \.isVideo), let url = APIClient.shared.absolute(m.url) else { return }
        let p = player ?? LoopingPlayer(url: url)
        player = p
        started = false
        p.play()
        // 실제로 프레임이 진행되기 시작하면 표시 (버퍼링 중 멈춘 첫 화면 방지)
        Task {
            for _ in 0..<80 {
                try? await Task.sleep(for: .milliseconds(50))
                guard isPlaying else { return }
                let t = p.player.currentTime().seconds   // 처음엔 nan 일 수 있음
                if p.player.timeControlStatus == .playing, t.isFinite, t > 0.04 { started = true; return }
            }
        }
    }

    private func stopPreview() { player?.pause(); started = false }
}

// MARK: - 상세

struct PostDetailView: View {
    let post: CommunityPost
    var onTag: (String) -> Void = { _ in }

    @Environment(AuthSession.self) private var auth
    @Environment(CommunityStore.self) private var community
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    private var isMine: Bool { auth.user?.id == post.author.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                authorRow.padding(.horizontal, 16).padding(.vertical, 12)
                TabView(selection: $page) {
                    ForEach(Array(post.media.enumerated()), id: \.element.id) { i, m in
                        MediaPage(media: m, active: page == i).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: post.media.count > 1 ? .automatic : .never))
                .frame(height: 440)
                .background(Color.black)

                VStack(alignment: .leading, spacing: 8) {
                    Text(post.title).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                    if let c = post.caption, !c.isEmpty {
                        Text(c).font(.system(size: 14)).foregroundStyle(Theme.ink.opacity(0.85))
                    }
                    if !post.tags.isEmpty {
                        FlowTags(tags: post.tags) { tag in onTag(tag) }
                    }
                    if let d = post.createdAt {
                        Text(d.formatted(.relative(presentation: .named))).font(.system(size: 12)).foregroundStyle(Theme.gray)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .alert("게시물을 삭제할까요?", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) { delete() }
            Button("취소", role: .cancel) {}
        }
        .alert("삭제하지 못했어요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var authorRow: some View {
        HStack(spacing: 10) {
            AsyncImage(url: APIClient.shared.absolute(post.author.profileImageUrl)) { $0.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Theme.red.opacity(0.7))
            }
            .frame(width: 34, height: 34).clipShape(Circle())
            Text(post.author.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if isMine {
                Button { confirmDelete = true } label: {
                    if deleting { ProgressView() } else { Image(systemName: "trash").foregroundStyle(Theme.gray) }
                }
                .disabled(deleting)
            }
        }
    }

    private func delete() {
        deleting = true
        Task {
            defer { deleting = false }
            do {
                try await auth.authorized { try await APIClient.shared.deleteCommunityPost(id: post.id, token: $0) }
                community.remove(post.id)
                dismiss()
            } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "잠시 후 다시 시도해 주세요." }
        }
    }
}

private struct MediaPage: View {
    let media: CommunityMedia
    let active: Bool
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if media.isVideo {
                VideoPlayer(player: player)
                    .onAppear {
                        if player == nil, let url = APIClient.shared.absolute(media.url) { player = AVPlayer(url: url) }
                        if active { player?.play() }
                    }
                    .onChange(of: active) { _, on in if on { player?.play() } else { player?.pause() } }
                    .onDisappear { player?.pause() }
            } else {
                AsyncImage(url: APIClient.shared.absolute(media.url)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").foregroundStyle(.white.opacity(0.4))
                    default: ProgressView().tint(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FlowTags: View {
    let tags: [String]
    let onTap: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    Button("#\(t)") { onTap(t) }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.red)
                }
            }
        }
    }
}
