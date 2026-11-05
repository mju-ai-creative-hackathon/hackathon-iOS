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
        #if DEBUG
        .task {   // 디버그 전용: `-openPost <uuid>` → 게시물 상세 바로 열기
            if let s = UserDefaults.standard.string(forKey: "openPost"), let id = UUID(uuidString: s), selected == nil,
               let p = try? await APIClient.shared.communityPost(id: id) { selected = p }
        }
        #endif
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
                    CachedImage(url: APIClient.shared.absolute(post.thumbnailUrl))
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
                HStack(spacing: 4) {
                    Text("SHORTS").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(height: 17)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.22)))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
                    if post.course != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "map.fill").font(.system(size: 7, weight: .bold))
                            Text("코스").font(.system(size: 9, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(height: 17)
                        .background(Capsule().fill(Theme.red.opacity(0.9)))
                    }
                }
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
    @Environment(AppStore.self) private var store
    @Environment(DiaryStore.self) private var diary
    @State private var showCourse = false
    @State private var importing = false
    @State private var importError: String?
    @State private var importDone = false

    private static let inProgressMessage = "이미 진행 중인 여정이 있어요. 마이 탭에서 종료한 뒤 다시 시도해 주세요."

    private var isMine: Bool { auth.user?.id == post.author.id }

    private func courseCard(_ course: CommunityLinkedCourse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.red)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.blueSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text("이 영상의 코스").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.red)
                    Text(course.title?.isEmpty == false ? course.title! : "연결된 코스")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                    Text("코스를 가져와 바로 여정을 시작할 수 있어요").font(.system(size: 12)).foregroundStyle(Theme.gray)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { showCourse = true } label: {
                    Text("코스 보기").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cream))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                if !isMine {
                    Button(action: startImport) {
                        ZStack {
                            if importing { ProgressView().tint(.white) }
                            else { Text("이 코스로 여정 시작").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.red))
                    }
                    .buttonStyle(.plain)
                    .disabled(importing)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
    }

    private func startImport() {
        guard auth.user != nil else { auth.logout(); return }
        guard !diary.isTracking else { importError = Self.inProgressMessage; return }
        importing = true
        Task {
            defer { importing = false }
            do {
                let result = try await auth.authorized { try await APIClient.shared.importCommunityCourse(postId: post.id, token: $0) }
                diary.adopt(result.diary)
                importDone = true
            } catch {
                if (error as? APIError)?.status == 409 { importError = Self.inProgressMessage }
                else { importError = (error as? LocalizedError)?.errorDescription ?? "잠시 후 다시 시도해 주세요." }
            }
        }
    }

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

                if let course = post.course {
                    courseCard(course).padding(.horizontal, 16).padding(.bottom, 16)
                }

                Rectangle().fill(Theme.line).frame(height: 0.5).padding(.horizontal, 16)
                PostComments(postId: post.id)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg)
        .sheet(isPresented: $showCourse) {
            if let c = post.course { NavigationStack { CourseDetailView(courseId: c.id) } }
        }
        .alert("여정을 시작할 수 없어요", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(importError ?? "") }
        .alert("여정을 시작했어요!", isPresented: $importDone) {
            Button("마이에서 보기") {
                dismiss()
                store.selectedTab = .tour
            }
            Button("확인", role: .cancel) {}
        } message: { Text("걸음과 발자취가 기록돼요") }
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


// MARK: - 댓글 (GET/POST/PATCH/DELETE /api/community/posts/{id}/comments)

private struct PostComments: View {
    let postId: UUID

    @Environment(AuthSession.self) private var auth
    @State private var comments: [CommunityComment] = []
    @State private var total = 0
    @State private var nextPage = 0
    @State private var hasNext = false
    @State private var loading = false
    @State private var loadError: String?

    @State private var text = ""
    @State private var editing: CommunityComment?
    @State private var sending = false
    @State private var deleting: CommunityComment?
    @State private var error: String?
    @FocusState private var focused: Bool

    private let api = APIClient.shared
    private static let maxLength = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("댓글").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                Text("\(total)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.red)
            }
            composer
            if comments.isEmpty {
                Group {
                    if loading { ProgressView().tint(Theme.red) }
                    else if let e = loadError {
                        VStack(spacing: 6) {
                            Text(e).font(.system(size: 13)).foregroundStyle(Theme.gray)
                            Button("다시 시도") { Task { await reload() } }
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                        }
                    } else {
                        Text("아직 댓글이 없어요. 첫 댓글을 남겨보세요!")
                            .font(.system(size: 13)).foregroundStyle(Theme.gray)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(comments) { c in row(c) }
                }
                if hasNext {
                    Button { Task { await loadMore() } } label: {
                        HStack(spacing: 6) {
                            if loading { ProgressView().controlSize(.small) }
                            Text("댓글 더 보기")
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gray)
                        .frame(maxWidth: .infinity).frame(height: 36)
                    }
                    .disabled(loading)
                }
            }
        }
        .padding(16)
        .padding(.bottom, 24)
        .task(id: postId) { await reload() }
        .alert("댓글을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("삭제", role: .destructive) { if let c = deleting { Task { await remove(c) } } }
            Button("취소", role: .cancel) {}
        }
        .alert("알림", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: 입력창

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder private var composer: some View {
        if auth.user == nil {
            Button { auth.logout() } label: {
                Text("로그인하고 댓글을 남겨보세요")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.blueSoft))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let e = editing {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
                        Text("댓글 수정 중").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("취소") { editing = nil; text = ""; focused = false }
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.red)
                    .id(e.id)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(editing == nil ? "댓글을 입력하세요" : "수정할 내용을 입력하세요", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.system(size: 14))
                        .focused($focused)
                        .onChange(of: text) { _, v in if v.count > Self.maxLength { text = String(v.prefix(Self.maxLength)) } }
                    Button { Task { await submit() } } label: {
                        Group {
                            if sending { ProgressView().tint(.white) }
                            else { Image(systemName: editing == nil ? "arrow.up" : "checkmark").font(.system(size: 13, weight: .heavy)) }
                        }
                        .foregroundStyle(.white).frame(width: 32, height: 32)
                        .background(Circle().fill(trimmed.isEmpty ? Theme.line : Theme.red))
                    }
                    .disabled(trimmed.isEmpty || sending)
                }
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                if text.count > Self.maxLength - 100 {
                    Text("\(text.count)/\(Self.maxLength)").font(.system(size: 11)).foregroundStyle(Theme.gray)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    // MARK: 댓글 한 줄

    private func row(_ c: CommunityComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: APIClient.shared.absolute(c.author.profileImageUrl)) { $0.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Theme.red.opacity(0.6))
            }
            .frame(width: 30, height: 30).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.author.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
                    if let d = c.createdAt {
                        Text(d.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11)).foregroundStyle(Theme.gray)
                    }
                    if c.isEdited { Text("수정됨").font(.system(size: 11)).foregroundStyle(Theme.gray) }
                }
                // 일반 텍스트로만 표시 (HTML 해석 X)
                Text(verbatim: c.content).font(.system(size: 14)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if auth.user?.id == c.author.id {
                Menu {
                    Button { editing = c; text = c.content; focused = true } label: { Label("수정", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = c } label: { Label("삭제", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gray)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: 동작

    private func reload() async {
        loading = true; loadError = nil
        defer { loading = false }
        do {
            let p = try await api.comments(postId: postId, page: 0)
            comments = p.content; total = p.totalElements; hasNext = p.hasNext; nextPage = 1
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "댓글을 불러오지 못했어요."
        }
    }

    private func loadMore() async {
        guard hasNext, !loading else { return }
        loading = true
        defer { loading = false }
        guard let p = try? await api.comments(postId: postId, page: nextPage) else { return }
        let known = Set(comments.map(\.id))
        comments += p.content.filter { !known.contains($0.id) }
        total = p.totalElements; hasNext = p.hasNext; nextPage += 1
    }

    private func submit() async {
        let body = trimmed
        guard !body.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            if let e = editing {
                let updated = try await auth.authorized {
                    try await api.editComment(postId: postId, commentId: e.id, content: body, token: $0)
                }
                if let i = comments.firstIndex(where: { $0.id == e.id }) { comments[i] = updated }
                editing = nil
            } else {
                let new = try await auth.authorized { try await api.addComment(postId: postId, content: body, token: $0) }
                // 오래된 순 목록 → 다 불러온 상태면 끝에 붙이고, 아니면 개수만 갱신
                if !hasNext { comments.append(new) }
                total += 1
            }
            text = ""; focused = false
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "댓글을 저장하지 못했어요."
        }
    }

    private func remove(_ c: CommunityComment) async {
        do {
            try await auth.authorized { try await api.deleteComment(postId: postId, commentId: c.id, token: $0) }
            comments.removeAll { $0.id == c.id }
            total = max(0, total - 1)
            if editing?.id == c.id { editing = nil; text = "" }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "댓글을 삭제하지 못했어요."
        }
    }
}
