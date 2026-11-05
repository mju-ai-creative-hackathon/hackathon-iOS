import SwiftUI
import MapKit

/// 탐색하기 탭: 지역 칩 + AI 맞춤 코스 입력 + 추천 코스 (Backend /api/courses)
struct TourView: View {
    @Environment(TourStore.self) private var tour
    @Environment(AuthSession.self) private var auth
    @Environment(AppStore.self) private var store
    @Environment(DiaryStore.self) private var diary
    @State private var prompt = ""
    @State private var savedTrip = false
    @State private var path: [Route] = []
    @State private var needsLogin = false
    @FocusState private var typing: Bool

    enum Route: Hashable { case course(Int64), recommendations }

    private let examples = ["성수에서 카페 투어하고 싶어", "비 오는 날 실내 위주로", "한강 노을 보는 데이트", "종로 전통시장 먹방"]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if diary.active != nil { activeTrip.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 4) }
                    hero
                    VStack(alignment: .leading, spacing: 0) {
                        regionChips.padding(.top, 14)
                        promptBar.padding(.top, 12).padding(.horizontal, 16)
                        exampleChips.padding(.top, 10)
                        if let e = tour.recommendError {
                            Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
                                .padding(.horizontal, 16).padding(.top, 8)
                        }
                        if !tour.recommendations.isEmpty { recentRecommendation.padding(.top, 18) }
                        curated.padding(.top, 26)
                        allCourses.padding(.top, 26)
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await tour.loadCourses() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .course(let id): CourseDetailView(courseId: id)
                case .recommendations: CourseDetailView(options: tour.recommendations)
                }
            }
        }
        .task { if tour.courses.isEmpty { await tour.load() } }
        #if DEBUG
        .task {   // 디버그 전용: `-openCourse 1` → 해당 코스 상세로
            let id = UserDefaults.standard.integer(forKey: "openCourse")
            if id > 0, path.isEmpty { path.append(.course(Int64(id))) }
        }
        #endif
        .overlay { if tour.isRecommending { RecommendingOverlay() } }
        .alert("로그인이 필요해요", isPresented: $needsLogin) {
            Button("로그인") { auth.logout() }
            Button("취소", role: .cancel) {}
        } message: { Text("AI 맞춤 코스와 코스 저장은 로그인 후 이용할 수 있어요.") }
        .alert("기록을 저장했어요", isPresented: $savedTrip) {
            Button("마이에서 보기") { store.selectedTab = .tour }
            Button("확인", role: .cancel) {}
        } message: { Text("마이 탭에서 오늘의 발자취를 확인할 수 있어요.") }
    }

    // MARK: 상단 바 (홈)
    private var header: some View {
        HStack(spacing: 18) {
            BrandLogo(size: 22)
            Spacer()
            Button { selectSaved() } label: {
                Image(systemName: tour.region == TourStore.savedFilter ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tour.region == TourStore.savedFilter ? Theme.red : Theme.ink)
            }
            .accessibilityLabel("저장한 코스")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Theme.bg)
    }

    // MARK: 진행 중인 일정
    private var activeTrip: some View {
        let a = diary.active!
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Theme.red).frame(width: 7, height: 7)
                Text("진행 중인 일정").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(Theme.red)
            }
            Text(a.title).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let sec = max(0, Int(ctx.date.timeIntervalSince(a.startedAt)))
                let elapsed = sec >= 3600
                    ? String(format: "%d:%02d:%02d", sec / 3600, sec / 60 % 60, sec % 60)
                    : String(format: "%02d:%02d", sec / 60, sec % 60)
                Text("\(diary.steps)걸음 · \(CourseFormat.distance(Int(diary.distanceMeters))) · ≈\(diary.kcal)kcal · \(elapsed) 경과")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.gray)
            }
            if let e = diary.tripError {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
            }
            HStack(spacing: 8) {
                if let cid = a.courseId {
                    Button { path.append(.course(cid)) } label: {
                        Text("코스 보기").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    }
                }
                Button {
                    Task { if await diary.finish() != nil { savedTrip = true } }
                } label: {
                    Group {
                        if diary.isBusy { ProgressView().tint(.white) }
                        else { Text("종료").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.red))
                }
                .disabled(diary.isBusy)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.blueSoft))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.red, lineWidth: 1))
    }

    // MARK: 상단 (흐린 서울 지도 + 제목)
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.555, longitude: 126.99),
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12))), interactionModes: [])
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .saturation(0.2).opacity(0.55)
                .frame(height: 190)
                .overlay(LinearGradient(colors: [Theme.bg.opacity(0.1), Theme.bg], startPoint: .center, endPoint: .bottom))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 4) {
                Text("SEOUL COURSE").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.red)
                Text("오늘은 어디를 걸어볼까요?").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("코스를 따라 촬영 미션을 모으면 숏폼이 완성돼요").font(.system(size: 13)).foregroundStyle(Theme.gray)
            }
            .padding(.horizontal, 16)
        }
    }

    private var regionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("전체", on: tour.region == nil) { Task { await tour.select(region: nil) } }
                ForEach(tour.regions, id: \.self) { r in
                    chip(r, on: tour.region == r) { Task { await tour.select(region: r) } }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: on ? .bold : .medium))
                .foregroundStyle(on ? .white : Theme.ink)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(on ? Theme.red : .white))
                .overlay(Capsule().strokeBorder(on ? .clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: AI 입력
    private var promptBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Theme.red)
            TextField("원하는 코스를 입력해 주세요", text: $prompt, axis: .vertical)
                .lineLimit(1...3)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit(send)
                .font(.system(size: 14))
            Button(action: send) {
                Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.line : Theme.red))
            }
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || tour.isRecommending)
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private var exampleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(examples, id: \.self) { e in
                    Button { prompt = e } label: {
                        Text(e).font(.system(size: 12)).foregroundStyle(Theme.gray)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(Theme.cream))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func send() {
        typing = false
        guard auth.user != nil else { needsLogin = true; return }
        let text = prompt
        Task {
            await tour.recommend(text)
            if !tour.recommendations.isEmpty { path.append(.recommendations) }
        }
    }

    private func selectSaved() {
        guard auth.user != nil else { needsLogin = true; return }
        Task { await tour.select(region: tour.region == TourStore.savedFilter ? nil : TourStore.savedFilter) }
    }

    // MARK: 방금 받은 AI 코스 다시 보기
    private var recentRecommendation: some View {
        Button { path.append(.recommendations) } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.red)
                    .frame(width: 40, height: 40).background(Circle().fill(Theme.blueSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 맞춤 코스 \(tour.recommendations.count)개").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                    Text(tour.recommendations.map(\.title).joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.gray).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gray)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.red.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: 추천 코스 (가로 카드)
    private var curatedTitle: String {
        switch tour.region {
        case nil: "서울에서 시작해 볼까요?"
        case TourStore.savedFilter?: "저장한 코스"
        case let r?: "\(r)에서 시작해 볼까요?"
        }
    }

    private var curated: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CURATED FOR YOU").font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.red)
                Text(curatedTitle).font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 16)

            if tour.courses.isEmpty {
                Group {
                    if tour.isLoading { ProgressView().tint(Theme.red) }
                    else if let e = tour.errorMessage {
                        VStack(spacing: 8) {
                            Text(e).font(.system(size: 13)).foregroundStyle(Theme.gray)
                            Button("다시 시도") { Task { await tour.loadCourses() } }
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.red)
                        }
                    } else {
                        Text(tour.region == TourStore.savedFilter ? "아직 저장한 코스가 없어요." : "이 지역 코스는 준비 중이에요.")
                            .font(.system(size: 13)).foregroundStyle(Theme.gray)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 200)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(tour.courses.prefix(6).enumerated()), id: \.element.id) { i, c in
                            NavigationLink(value: Route.course(c.id)) { CuratedCard(course: c, rank: i + 1) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder private var allCourses: some View {
        if tour.courses.count > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("코스 둘러보기").font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                ForEach(tour.courses) { c in
                    NavigationLink(value: Route.course(c.id)) { CourseRow(course: c) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - 카드

enum CourseFormat {
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)분" : (m == 0 ? "\(h)시간" : "\(h)시간 \(m)분")
    }
    static func distance(_ meters: Int) -> String {
        meters < 1000 ? "\(meters)m" : String(format: "%.1fkm", Double(meters) / 1000)
    }
    static func cost(_ won: Int?) -> String {
        guard let won else { return "-" }
        return won == 0 ? "무료" : "₩" + won.formatted(.number)
    }
    static func imageURL(_ s: String?) -> URL? {
        guard let s else { return nil }
        return s.hasPrefix("http") ? URL(string: s) : APIClient.shared.absolute(s)
    }
}

private struct CuratedCard: View {
    let course: CourseSummary
    let rank: Int
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(Theme.cream)
                .overlay {
                    AsyncImage(url: CourseFormat.imageURL(course.thumbnailUrl)) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Image(systemName: "photo").foregroundStyle(Theme.line) }
                    }
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white).lineLimit(2)
                Text("\(course.region ?? "서울") · \(CourseFormat.duration(course.totalMinutes)) · \(course.stopCount)곳")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(12)
        }
        .frame(width: 210, height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("추천 코스 \(rank)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                .padding(.horizontal, 8).frame(height: 22)
                .background(Capsule().fill(.white))
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if course.saved {
                Image(systemName: "bookmark.fill").font(.system(size: 13)).foregroundStyle(.white)
                    .shadow(radius: 2).padding(12)
            }
        }
    }
}

private struct CourseRow: View {
    let course: CourseSummary
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: CourseFormat.imageURL(course.thumbnailUrl)) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() } else { Theme.cream }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(course.region ?? "서울").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                    if course.source == "AI" {
                        Text("AI").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 5).background(Capsule().fill(Theme.red))
                    }
                    if let d = course.distanceMeters {
                        Text("· \(CourseFormat.distance(d))").font(.system(size: 11)).foregroundStyle(Theme.gray)
                    }
                }
                Text(course.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(course.stopNames.joined(separator: " → "))
                    .font(.system(size: 12)).foregroundStyle(Theme.gray).lineLimit(1)
                Text("\(CourseFormat.duration(course.totalMinutes)) · \(CourseFormat.cost(course.estimatedCost))")
                    .font(.system(size: 11)).foregroundStyle(Theme.gray)
            }
            Spacer(minLength: 0)
            if course.saved { Image(systemName: "bookmark.fill").font(.system(size: 13)).foregroundStyle(Theme.red) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - AI 추천 로딩 (30~40초)

struct RecommendingOverlay: View {
    var title = "AI가 맞춤 코스를 짜고 있어요"
    @State private var tick = 0
    private let lines = ["요청을 읽고 있어요", "서울 곳곳의 장소를 찾는 중", "동선과 이동 시간을 맞추는 중",
                         "장소마다 촬영 미션을 만드는 중", "거의 다 됐어요"]
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Theme.blueSoft, lineWidth: 6).frame(width: 84, height: 84)
                    Circle().trim(from: 0, to: min(0.95, Double(tick) / 40))
                        .stroke(Theme.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 84, height: 84)
                        .animation(.linear(duration: 1), value: tick)
                    Image(systemName: "map.fill").font(.system(size: 26)).foregroundStyle(Theme.red)
                        .symbolEffect(.pulse)
                }
                Text(title).font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(lines[min(lines.count - 1, tick / 8)] + "…")
                    .font(.system(size: 14)).foregroundStyle(Theme.gray)
                    .contentTransition(.opacity).animation(.easeInOut, value: tick / 8)
                Text("30~40초 정도 걸려요").font(.system(size: 12)).foregroundStyle(Theme.gray.opacity(0.8))
            }
        }
        .onReceive(timer) { _ in tick += 1 }
        .transition(.opacity)
    }
}
