import SwiftUI
import PhotosUI

/// 만들기 탭 (와이어프레임 '만들기' 1·2·완성)
/// STEP 01 사진 선택 → STEP 02 스타일(무드·음악) → 완성(AI 생성 → 미리보기 → 공유)
struct CreateView: View {
    enum Step: Int { case photos = 1, style, done }

    @Environment(AppStore.self) private var store
    @Environment(AuthSession.self) private var auth
    @State private var step: Step = .photos
    @State private var request = ReelGenerationRequest(source: .gallery, media: [])
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isPicking = false
    @State private var isLoading = false
    @State private var showHelp = false
    @State private var showMusic = false

    // 생성 상태
    @State private var progress: Double = 0
    @State private var stage = "준비 중"
    @State private var result: Reel?
    @State private var genError: String?
    @State private var genTask: Task<Void, Never>?
    @State private var shared = false
    @State private var resultVideo: URL?          // 서버(AI)가 만든 결과 영상
    @State private var aiUnavailable = false      // AI 서버 미연결 → 기기 미리보기 제안
    @State private var isLocalPreview = false
    @State private var needsLogin = false
    @State private var isSharing = false
    @State private var shareError: String?
    @State private var pinned: [MediaItem] = []   // 코스 미션에서 넘어온 소스 (피커와 별개)

    /// 백엔드 제작 조건: 5~20개
    static let minCount = 5
    static let maxCount = 20

    var body: some View {
        VStack(spacing: 0) {
            navBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .photos: photosStep
                    case .style: styleStep
                    case .done: doneStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            if step != .done { bottomButton }
        }
        .background(background.ignoresSafeArea())
        .photosPicker(isPresented: $isPicking, selection: $pickerItems,
                      maxSelectionCount: Self.maxCount, selectionBehavior: .ordered,
                      matching: .any(of: [.images, .videos]))
        .onChange(of: pickerItems) { _, items in Task { await load(items) } }
        .sheet(isPresented: $showHelp) { HelpSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $showMusic) {
            MusicSheet(selected: $request.music).presentationDetents([.medium])
        }
        .animation(.snappy(duration: 0.3), value: step)
        .onAppear(perform: consumeDraft)
        .onChange(of: store.createDraft != nil) { _, has in if has { consumeDraft() } }
        .alert("로그인이 필요해요", isPresented: $needsLogin) {
            Button("로그인") { auth.logout() }
            Button("취소", role: .cancel) {}
        } message: { Text("숏폼 제작은 로그인 후 이용할 수 있어요.") }
        #if DEBUG
        .task {
            // 디버그 전용: `-createDemo 1|2|3` → 사진 5장 미리 넣고 해당 STEP 으로
            let n = UserDefaults.standard.integer(forKey: "createDemo")
            guard n > 0, request.media.isEmpty else { return }
            var items: [MediaItem] = []
            for i in 1...5 {
                if let url = URL(string: "https://picsum.photos/seed/sl\(i)/800/1000"),
                   let (d, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: d) {
                    items.append(MediaItem(kind: .photo(img)))
                }
            }
            request.media = items
            if n >= 2 { step = .style }
            if n >= 3 { step = .done; startGeneration() }
        }
        #endif
    }

    private var background: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.blueSoft.opacity(0.9), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 360)
        }
    }

    // MARK: 상단 바
    private var navBar: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(step == .done ? "완성" : "만들기").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                HStack {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                            .frame(width: 40, height: 40, alignment: .leading)
                    }
                    Spacer()
                    if step == .photos {
                        Button { showHelp = true } label: {
                            Text("?").font(.system(size: 15, weight: .bold))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(.white))
                                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                        }
                    }
                }
                .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            Rectangle().fill(Theme.line.opacity(0.7)).frame(height: 0.5)
        }
    }

    private func eyebrow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
            Text(text).font(.system(size: 11, weight: .heavy)).tracking(0.8)
        }
        .foregroundStyle(Theme.red)
    }

    private func titleBlock(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.ink).lineSpacing(2).padding(.top, 10)
            Text(sub).font(.system(size: 13)).foregroundStyle(Theme.gray).padding(.top, 10)
        }
    }

    // MARK: - STEP 01 사진 선택
    private var photosStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("SEOLLOG SHORTS").padding(.top, 24)
            titleBlock("서울의 순간을\n나만의 숏폼으로", "사진만 고르면 리듬에 맞춰 자연스럽게 이어드려요.")
            StepIndicator(current: 1).padding(.top, 26)
            photoCard.padding(.top, 24)
        }
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("사진을 골라주세요").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("5~\(Self.maxCount)장 · 세로 사진을 추천해요").font(.system(size: 12)).foregroundStyle(Theme.gray)
                }
                Spacer()
                Text("\(request.media.count)/\(Self.maxCount)")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.red).padding(.top, 10)
            }
            Group {
                if request.media.isEmpty && !isLoading { emptyPicker } else { selectedRow }
            }
            .padding(.top, 18)
        }
        .padding(20)
        .frame(minHeight: 300, alignment: .top)
        .modifier(WhiteCard())
    }

    private var emptyPicker: some View {
        Button { isPicking = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.blueSoft.opacity(0.6), Theme.blueSoft],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.red.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                FloatingPhoto().rotationEffect(.degrees(-10)).offset(x: -110, y: -36)
                FloatingPhoto().rotationEffect(.degrees(8)).offset(x: 110, y: 58)
                VStack(spacing: 0) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.red))
                        .shadow(color: Theme.red.opacity(0.35), radius: 8, y: 4)
                    Text("사진 선택하기").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 14)
                    Text("기기의 사진 보관함에서 불러와요").font(.system(size: 11)).foregroundStyle(Theme.gray).padding(.top, 6)
                }
            }
            .frame(height: 232)
        }
        .buttonStyle(.plain)
    }

    private var selectedRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(request.media.enumerated()), id: \.element.id) { i, item in
                    thumb(item, number: i + 1)
                }
                if isLoading { ProgressView().tint(Theme.red).frame(width: 88, height: 134) }
                Button { isPicking = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 18)).foregroundStyle(Theme.red)
                        Text("다시 선택").font(.system(size: 11)).foregroundStyle(Theme.gray)
                    }
                    .frame(width: 88, height: 134)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func thumb(_ item: MediaItem, number: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = item.thumbnail { Image(uiImage: img).resizable().scaledToFill() } else { Theme.cream }
            }
            .frame(width: 88, height: 134)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if case .video = item.kind {
                    Image(systemName: "video.fill").font(.system(size: 10)).foregroundStyle(.white).padding(6).shadow(radius: 2)
                }
            }
            NumberBadge(number: number).padding(6)
        }
        .contextMenu {
            Button("빼기", systemImage: "minus.circle", role: .destructive) { remove(item) }
        }
    }

    // MARK: - STEP 02 스타일
    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("STEP 02").padding(.top, 24)
            titleBlock("어떤 분위기로 담을까요?", "사진에 어울리는 무드와 음악을 선택해 보세요.")
            StepIndicator(current: 2).padding(.top, 22)

            PreviewBanner(image: request.media.first?.thumbnail, style: request.style)
                .padding(.top, 22)

            HStack {
                Text("영상 스타일").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("1개 선택").font(.system(size: 11)).foregroundStyle(Theme.gray)
            }
            .padding(.top, 22)

            HStack(spacing: 8) {
                ForEach(ReelStyle.allCases) { s in
                    MoodCard(style: s, selected: request.style == s) {
                        withAnimation(.snappy(duration: 0.2)) { request.style = s }
                    }
                }
            }
            .padding(.top, 10)

            Text("분위기").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReelMood.allCases) { m in
                        let on = request.mood == m
                        Button { request.mood = m } label: {
                            Text(m.rawValue).font(.system(size: 13, weight: on ? .bold : .medium))
                                .foregroundStyle(on ? .white : Theme.ink)
                                .padding(.horizontal, 16).frame(height: 34)
                                .background(Capsule().fill(on ? Theme.red : .white))
                                .overlay(Capsule().strokeBorder(on ? .clear : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 10)

            Button { showMusic = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "music.note").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.red)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.blueSoft))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("배경 음악").font(.system(size: 11)).foregroundStyle(Theme.gray)
                        Text(request.music.rawValue).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Text(request.music.length).font(.system(size: 12)).foregroundStyle(Theme.gray)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gray)
                }
                .padding(14)
                .modifier(WhiteCard(radius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }

    // MARK: - 완성
    private var doneStep: some View {
        VStack(spacing: 0) {
            ZStack {
                if result != nil {
                    Circle().fill(Color(red: 0.24, green: 0.55, blue: 0.38)).frame(width: 40, height: 40)
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                } else if genError != nil {
                    Circle().fill(Theme.red).frame(width: 40, height: 40)
                    Image(systemName: "exclamationmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Circle().stroke(Theme.line, lineWidth: 3).frame(width: 40, height: 40)
                    Circle().trim(from: 0, to: progress).stroke(Theme.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 40, height: 40)
                    Text("\(Int(progress * 100))").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                }
            }
            .padding(.top, 28)

            Text(result != nil ? "서울의 순간이 완성됐어요" : (genError != nil ? "숏폼을 만들지 못했어요" : "숏폼을 만들고 있어요"))
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink).padding(.top, 14)
            Text(result != nil ? "선택한 사진과 스타일로 만든 숏폼 미리보기예요." : (genError ?? "\(stage)…"))
                .font(.system(size: 12)).foregroundStyle(Theme.gray).padding(.top, 8)
                .multilineTextAlignment(.center)

            StepIndicator(current: 3, finished: result != nil).padding(.top, 22)

            PhonePreview(images: request.media.compactMap(\.thumbnail), style: request.style,
                         isReady: result != nil, progress: progress, videoURL: resultVideo)
                .padding(.top, 24)

            if result != nil {
                Button(action: shareResult) {
                    HStack(spacing: 6) {
                        if isSharing { ProgressView().tint(.white) }
                        else { Image(systemName: shared ? "checkmark" : "paperplane.fill").font(.system(size: 13, weight: .bold)) }
                        Text(shared ? "커뮤니티에 공유했어요" : (isSharing ? "올리는 중…" : "커뮤니티에 공유하기"))
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(shared ? Theme.gray : Theme.red))
                }
                .disabled(shared || isSharing)
                .padding(.top, 22)
                if let shareError {
                    Text(shareError).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.top, 8)
                }
                if isLocalPreview {
                    Text("AI 서버 연결 전이라 기기에서 만든 미리보기예요.")
                        .font(.system(size: 11)).foregroundStyle(Theme.gray).padding(.top, 8)
                }
            } else if aiUnavailable {
                Button(action: startLocalPreview) {
                    Text("기기에서 미리보기 만들기")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.red))
                }
                .padding(.top, 22)
                Button("다시 시도") { startGeneration() }
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red).padding(.top, 12)
            } else if genError != nil {
                Button("다시 시도") { startGeneration() }
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.red).padding(.top, 20)
            }

            Button("다른 숏폼 만들기") { reset() }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gray).underline()
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 하단 버튼
    private var bottomButton: some View {
        let enabled = step == .photos ? request.media.count >= Self.minCount && !isLoading : true
        let title: String = step == .style ? "이 스타일로 만들기"
            : (enabled ? "스타일 고르기" : "사진을 \(Self.minCount)장 이상 선택해 주세요")
        return Button(action: next) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: step == .style ? "sparkles" : "chevron.right").font(.system(size: 13, weight: .bold))
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(enabled ? .white : Theme.gray)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(enabled ? Theme.red : Color(red: 0.91, green: 0.90, blue: 0.89)))
            .shadow(color: enabled ? Theme.red.opacity(0.3) : .clear, radius: 10, y: 4)
        }
        .disabled(!enabled)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        .animation(.snappy, value: enabled)
    }

    // MARK: 액션
    private func next() {
        switch step {
        case .photos: step = .style
        case .style:
            // 제작은 로그인 필요 (업로드 원본은 본인만 조회 가능)
            guard auth.user != nil else { needsLogin = true; return }
            step = .done; startGeneration()
        case .done: break
        }
    }

    private func back() {
        switch step {
        case .photos: store.selectedTab = .home
        case .style: step = .photos
        case .done: genTask?.cancel(); step = .style
        }
    }

    /// 실제 제작: 백엔드에 업로드 → AI 제작 → 결과 영상
    private func startGeneration() {
        genTask?.cancel()
        result = nil; resultVideo = nil; genError = nil; aiUnavailable = false; isLocalPreview = false
        progress = 0; stage = "준비 중"; shared = false
        if request.caption.isEmpty { request.caption = request.style.headline }
        let req = request
        let pipeline = ShortformPipeline(auth: auth)
        genTask = Task {
            do {
                let url = try await pipeline.run(req, title: req.caption) { p, s in
                    withAnimation(.linear(duration: 0.2)) { progress = p }
                    stage = s
                }
                let reel = Reel(author: MockData.me, content: .remoteVideo(url), caption: req.caption, location: nil,
                                musicTitle: req.music == .none ? "원본 오디오" : "\(req.music.rawValue) · 설로그",
                                likeCount: 0, commentCount: 0, isMine: true)
                withAnimation(.spring(duration: 0.4)) { resultVideo = url; result = reel }
            } catch is CancellationError {
            } catch ShortformPipeline.Failure.renderingUnavailable {
                aiUnavailable = true
                genError = "영상 제작 서버가 아직 연결되지 않았어요.\n대신 기기에서 미리보기를 만들 수 있어요."
            } catch {
                genError = (error as? LocalizedError)?.errorDescription ?? "잠시 후 다시 시도해 주세요."
            }
        }
    }

    /// AI 서버 미연결 시 대안: 기기에서 사진 슬라이드 미리보기 (서버에 올리지 않음)
    private func startLocalPreview() {
        genTask?.cancel()
        genError = nil; aiUnavailable = false; progress = 0; stage = "미리보기 만드는 중"
        let req = request
        genTask = Task {
            do {
                let reel = try await store.generator.generate(req) { p in
                    withAnimation(.linear(duration: 0.1)) { progress = p.fraction }
                    stage = p.stage
                }
                withAnimation(.spring(duration: 0.4)) { isLocalPreview = true; result = reel }
            } catch is CancellationError {
            } catch { genError = "미리보기를 만들지 못했어요." }
        }
    }

    /// 커뮤니티 게시 (POST /api/community/posts) — 영상 전용: video + cover 사진
    /// AI 결과 영상이 있으면 그걸 내려받아 올리고, 기기 미리보기면 고른 사진으로 mp4 를 만들어 올린다.
    private func shareResult() {
        guard result != nil, !shared, !isSharing else { return }
        guard auth.user != nil else { needsLogin = true; return }
        isSharing = true; shareError = nil
        let req = request, remote = resultVideo
        Task {
            defer { isSharing = false }
            do {
                let stills = req.media.compactMap(\.thumbnail)
                guard let first = stills.first else { throw ShortformPipeline.Failure.failed("올릴 사진이 없어요.") }
                let videoData: Data
                if let remote {
                    videoData = try await URLSession.shared.data(from: remote).0
                } else {
                    let local = try await SlideshowExporter.export(stills)
                    defer { try? FileManager.default.removeItem(at: local) }
                    videoData = try Data(contentsOf: local)
                }
                guard videoData.count <= 100 * 1_048_576 else { throw ShortformPipeline.Failure.fileTooLarge("영상이 100MB를 넘어요.") }
                let video = UploadFile(data: videoData, filename: "shortform.mp4", mimeType: "video/mp4")
                let cover = try ShortformPipeline.uploadFile(MediaItem(kind: .photo(first)), index: 0,
                                                             maxImage: 10_485_760, maxVideo: 0)
                let title = String((req.caption.isEmpty ? req.style.headline : req.caption).prefix(100))
                var tags = ["서울", req.style.rawValue, req.mood.rawValue]
                if case .tour = req.source { tags.insert("도장깨기", at: 1) }
                let body = CommunityCreateBody(title: title, caption: nil, tags: tags)
                _ = try await auth.authorized {
                    try await APIClient.shared.createCommunityPost(body, video: video, cover: cover, token: $0)
                }
                withAnimation { shared = true }
            } catch {
                shareError = (error as? LocalizedError)?.errorDescription ?? "공유하지 못했어요. 다시 시도해 주세요."
            }
        }
    }

    private func reset() {
        genTask?.cancel()
        request = ReelGenerationRequest(source: .gallery, media: [])
        pinned = []
        pickerItems = []; result = nil; resultVideo = nil; genError = nil; aiUnavailable = false
        isLocalPreview = false; progress = 0; shared = false
        step = .photos
    }

    private func remove(_ item: MediaItem) {
        if let p = pinned.firstIndex(where: { $0.id == item.id }) {
            pinned.remove(at: p)
            request.media.removeAll { $0.id == item.id }
            if pinned.isEmpty { request.source = .gallery }
            return
        }
        guard let i = request.media.firstIndex(where: { $0.id == item.id }) else { return }
        request.media.remove(at: i)
        let pi = i - pinned.count
        if pickerItems.indices.contains(pi) { pickerItems.remove(at: pi) }
    }

    /// 탐색하기에서 넘어온 코스 미션 사진·영상을 앞에 고정
    private func consumeDraft() {
        guard let draft = store.createDraft else { return }
        store.createDraft = nil
        genTask?.cancel()
        pickerItems = []; result = nil; resultVideo = nil; genError = nil; shared = false
        pinned = draft.media
        request = ReelGenerationRequest(source: .tour(courseId: draft.courseId, missionIds: draft.missionIds),
                                        media: draft.media)
        request.caption = String(draft.title.prefix(100))
        step = draft.media.count >= Self.minCount ? .style : .photos
    }

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { request.media = pinned; return }
        isLoading = true
        var loaded: [MediaItem] = []
        for item in items {
            if let (m, _) = await MediaImport.load(item) { loaded.append(m) }
        }
        request.media = pinned + loaded
        isLoading = false
    }
}

// MARK: - 공용 소품

private struct WhiteCard: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 14, y: 4))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line.opacity(0.6), lineWidth: 1))
    }
}

private struct NumberBadge: View {
    let number: Int
    var body: some View {
        Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Theme.red))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
    }
}

private struct StepIndicator: View {
    let current: Int
    var finished = false
    private let titles = ["사진 선택", "스타일", "완성"]
    private let green = Color(red: 0.24, green: 0.55, blue: 0.38)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<3) { i in
                let n = i + 1
                let done = n < current || (finished && n == current)
                let active = n == current && !finished
                VStack(spacing: 8) {
                    ZStack {
                        if active { Circle().fill(Theme.red.opacity(0.15)).frame(width: 36, height: 36) }
                        Circle().fill(done ? green : (active ? Theme.red : .white)).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(done || active ? .clear : Theme.line, lineWidth: 1))
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        } else {
                            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(active ? .white : Theme.gray)
                        }
                    }
                    .frame(width: 36, height: 36)
                    Text(titles[i]).font(.system(size: 12, weight: active ? .bold : .medium))
                        .foregroundStyle(active ? Theme.red : (done ? Theme.ink : Theme.gray))
                        .fixedSize()
                }
                .frame(width: 60)
                if i < 2 {
                    Rectangle().fill(n < current ? green.opacity(0.5) : Theme.line)
                        .frame(height: 1).frame(maxWidth: .infinity).padding(.top, 18)
                }
            }
        }
    }
}

/// STEP 02 상단 미리보기 배너
private struct PreviewBanner: View {
    let image: UIImage?
    let style: ReelStyle
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { Theme.ink }
            }
            .frame(maxWidth: .infinity).frame(height: 170)
            .clipped()
            .overlay(StyleFilter(style: style))
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 4) {
                Text(style.tagline).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.white.opacity(0.85))
                Text(style.headline).font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
            }
            .padding(14)
        }
        .overlay(alignment: .topLeading) {
            Text("PREVIEW").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.5)))
                .padding(10)
        }
        .overlay {
            Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.black.opacity(0.3)))
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: style)
    }
}

/// 무드별 색감 오버레이 (실제 필터는 백엔드 AI 가 적용 — 미리보기용 근사치)
private struct StyleFilter: View {
    let style: ReelStyle
    var body: some View {
        switch style {
        case .cinematic: LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.3).opacity(0.35), Color(red: 0.6, green: 0.2, blue: 0.1).opacity(0.15)], startPoint: .top, endPoint: .bottom)
        case .dynamic: Color(red: 0.9, green: 0.3, blue: 0.2).opacity(0.12)
        case .vlog: Color(red: 0.75, green: 0.55, blue: 0.3).opacity(0.22).blendMode(.multiply)
        case .minimal: Color(white: 0.95).opacity(0.22)
        }
    }
}

private struct MoodCard: View {
    let style: ReelStyle
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: URL(string: "https://picsum.photos/seed/\(style.thumbnailSeed)/240/160")) {
                    $0.resizable().scaledToFill()
                } placeholder: { Theme.cream }
                .frame(height: 52).frame(maxWidth: .infinity).clipped()
                .overlay(StyleFilter(style: style))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(Circle().fill(Theme.red)).padding(4)
                    }
                }
                Text(style.rawValue).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink).padding(.top, 8)
                Text(style.summary).font(.system(size: 9)).foregroundStyle(Theme.gray)
                    .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 2)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.red : Theme.line, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// 완성 화면의 9:16 폰 미리보기
private struct PhonePreview: View {
    let images: [UIImage]
    let style: ReelStyle
    let isReady: Bool
    let progress: Double
    var videoURL: URL? = nil
    @State private var playing = true
    @State private var player: LoopingPlayer?

    var body: some View {
        ZStack {
            if isReady, let player {
                PlayerLayerView(player: player.player)
            } else if isReady {
                SlideshowReelView(images: images, secondsPerImage: 2, isPlaying: playing)
            } else if let first = images.first {
                Image(uiImage: first).resizable().scaledToFill().blur(radius: 6)
            } else { Theme.ink }
        }
        .frame(width: 200, height: 356)
        .clipped()
        .overlay(StyleFilter(style: style))
        .overlay(LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 0) {
                Text("설로그").foregroundStyle(.white)
                Text(".").foregroundStyle(Theme.orange)
            }
            .font(.system(size: 11, weight: .heavy)).padding(12)
        }
        .overlay {
            if isReady {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 14)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(.black.opacity(0.3)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2))
                        .opacity(playing ? 0.0001 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            } else {
                ProgressView().tint(.white).controlSize(.large)
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(style.tagline).font(.system(size: 8, weight: .heavy)).tracking(1).foregroundStyle(.white.opacity(0.85))
                Text(style.headline).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                Text("서울의 사진을 기록해요").font(.system(size: 9)).foregroundStyle(.white.opacity(0.8))
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: g.size.width * (isReady ? 0.35 : progress))
                        }
                }
                .frame(height: 2).padding(.top, 6)
            }
            .padding(12)
        }
        .onChange(of: videoURL, initial: true) { _, url in
            player?.pause()
            player = url.map { LoopingPlayer(url: $0) }
            if playing { player?.play() }
        }
        .onChange(of: playing) { _, on in if on { player?.play() } else { player?.pause() } }
        .onDisappear { player?.pause() }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.ink, lineWidth: 5))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }
}

private struct MusicSheet: View {
    @Binding var selected: MusicMood
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("배경 음악").font(.system(size: 18, weight: .bold)).padding(.bottom, 14)
            ForEach(MusicMood.allCases) { m in
                Button { selected = m; dismiss() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: m == .none ? "speaker.slash" : "music.note")
                            .foregroundStyle(Theme.red).frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.blueSoft))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.rawValue).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                            Text(m.mood).font(.system(size: 11)).foregroundStyle(Theme.gray)
                        }
                        Spacer()
                        Text(m.length).font(.system(size: 12)).foregroundStyle(Theme.gray)
                        if selected == m { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red) }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(24)
        .presentationDragIndicator(.visible)
    }
}

private struct FloatingPhoto: View {
    var body: some View {
        Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(Theme.red.opacity(0.45))
            .frame(width: 44, height: 50)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

private struct HelpSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("숏폼은 이렇게 만들어져요").font(.system(size: 18, weight: .bold))
            row("1", "사진 선택", "\(CreateView.minCount)~\(CreateView.maxCount)장을 골라요. 고른 순서대로 이어져요.")
            row("2", "스타일", "영상 스타일·분위기·배경 음악을 골라요.")
            row("3", "완성", "AI가 리듬에 맞춰 편집하면 미리 보고 커뮤니티에 공유해요.")
            Spacer()
        }
        .padding(24)
        .presentationDragIndicator(.visible)
    }
    private func row(_ n: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(Theme.red))
            VStack(alignment: .leading, spacing: 3) {
                Text(t).font(.system(size: 15, weight: .bold))
                Text(d).font(.system(size: 13)).foregroundStyle(Theme.gray)
            }
        }
    }
}
