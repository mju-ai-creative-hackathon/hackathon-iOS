import SwiftUI
import MapKit
import CoreLocation

/// 홈 (와이어프레임 '홈'): 유저 지도 + AI 맞춤 코스 입력 + 숏폼 배너 + 추천 코스 (Backend /api/courses)
struct TourView: View {
    @Environment(TourStore.self) private var tour
    @Environment(AuthSession.self) private var auth
    @Environment(AppStore.self) private var store
    @Environment(DiaryStore.self) private var diary
    @State private var prompt = ""
    @State private var savedTrip = false
    @State private var path: [Route] = []
    @State private var needsLogin = false
    @State private var district: String?
    @State private var camera: MapCameraPosition = .userLocation(fallback: Self.seoulFallback)
    @FocusState private var typing: Bool

    enum Route: Hashable { case course(Int64), recommendations, all }

    private static let seoulFallback: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.978),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))

    private let examples = ["성수에서 카페 투어하고 싶어", "비 오는 날 실내 위주로", "한강 노을 보는 데이트", "종로 전통시장 먹방"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    header(proxy)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            if diary.active != nil { activeTrip.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8) }
                            userMap.padding(.horizontal, 16).padding(.top, 4)
                            intro.padding(.horizontal, 16).padding(.top, 22)
                            promptBar.id("prompt").padding(.top, 14).padding(.horizontal, 16)
                            exampleChips.padding(.top, 8)
                            if let e = tour.recommendError {
                                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
                                    .padding(.horizontal, 16).padding(.top, 8)
                            }
                            if !tour.recommendations.isEmpty { recentRecommendation.padding(.top, 16) }
                            HomeShortsBanner { store.selectedTab = .create }
                                .padding(.horizontal, 16).padding(.top, 26)
                            whatToDo.padding(.top, 32)
                        }
                        .padding(.bottom, 30)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .refreshable { await tour.loadCourses() }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .course(let id): CourseDetailView(courseId: id)
                case .recommendations: CourseDetailView(options: tour.recommendations)
                case .all: AllCoursesView()
                }
            }
        }
        .task { if tour.courses.isEmpty { await tour.load() } }
        .task(id: coordinateKey) { await reverseGeocode() }
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
        } message: { Text("AI 맞춤 코스는 로그인 후 이용할 수 있어요.") }
        .alert("기록을 저장했어요", isPresented: $savedTrip) {
            Button("마이에서 보기") { store.selectedTab = .tour }
            Button("확인", role: .cancel) {}
        } message: { Text("마이 탭에서 오늘의 발자취를 확인할 수 있어요.") }
    }

    // MARK: 상단 바 (고정)
    private func header(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 18) {
            BrandLogo(size: 22)
            Spacer()
            Button {
                withAnimation { proxy.scrollTo("prompt", anchor: .center) }
                typing = true
            } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium))
            }
            .accessibilityLabel("코스 검색")
            Image(systemName: "bell").font(.system(size: 20, weight: .medium))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Theme.red).frame(width: 7, height: 7).offset(x: 1, y: -1)
                }
                .accessibilityLabel("알림")
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

    // MARK: 유저의 지도 (현재 위치 + 진행 중 일정 경로)
    private var routeCoordinates: [CLLocationCoordinate2D] {
        diary.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var userMap: some View {
        Map(position: $camera) {
            UserAnnotation()
            if diary.active != nil, diary.points.count > 1 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Theme.red, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Button { recenter() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.system(size: 11, weight: .semibold))
                    Text("내 위치").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(.white).shadow(color: .black.opacity(0.12), radius: 4, y: 1))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .onChange(of: diary.points.count) { _, _ in
            if diary.active != nil, diary.points.count > 1 { withAnimation { camera = .automatic } }
        }
        .onChange(of: diary.active == nil) { _, ended in
            if ended { recenter() }
        }
        .onAppear {
            if diary.active != nil, diary.points.count > 1 { camera = .automatic }
        }
    }

    private func recenter() {
        tour.location.request()
        withAnimation { camera = .userLocation(fallback: Self.seoulFallback) }
    }

    // MARK: 인트로
    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("오늘, 서울 어디로 떠나볼까요?")
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
            Text("\(district ?? "서울 어디서든")부터 지금 내게 어울리는 서울의 장소를 발견해 보세요.")
                .font(.system(size: 13)).foregroundStyle(Theme.gray)
        }
    }

    private var coordinateKey: String {
        guard let c = tour.location.coordinate else { return "none" }
        return String(format: "%.3f,%.3f", c.latitude, c.longitude)
    }

    private func reverseGeocode() async {
        guard let c = tour.location.coordinate else { return }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: c.latitude, longitude: c.longitude), preferredLocale: Locale(identifier: "ko_KR"))
        guard let p = marks?.first else { return }
        if let name = p.subLocality ?? p.locality, !name.isEmpty { district = name }
    }

    // MARK: AI 입력
    private var promptBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Theme.red)
            TextField("원하는 코스를 설명해 주세요", text: $prompt, axis: .vertical)
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
                        Text(e).font(.system(size: 11)).foregroundStyle(Theme.gray)
                            .padding(.horizontal, 9).frame(height: 24)
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

    // MARK: 서울에서 뭐 하지?
    private var whatToDo: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("서울에서 뭐 하지?").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text("취향에 맞는 장소를 발견해 보세요.").font(.system(size: 13)).foregroundStyle(Theme.gray)
                }
                Spacer()
                Button { path.append(.all) } label: {
                    HStack(spacing: 2) {
                        Text("모두 보기")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            regionChips.padding(.top, 14)

            HStack(spacing: 4) {
                Image(systemName: "sparkles").foregroundStyle(Theme.red)
                Text(curationLine).foregroundStyle(Theme.gray)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16).padding(.top, 14)

            coursePreview.padding(.top, 12)
        }
    }

    private var curationLine: String {
        if let r = tour.region { return "\(r) 샘플 큐레이션" }
        return "처음 만나는 서울을 위한 샘플 큐레이션"
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

    @ViewBuilder private var coursePreview: some View {
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
                    Text("이 지역 코스는 준비 중이에요.")
                        .font(.system(size: 13)).foregroundStyle(Theme.gray)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 200)
        } else {
            HomeCoursePreview(courses: tour.courses, onOpen: { path.append(.course($0)) })
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - 모든 코스 (모두 보기)

private struct AllCoursesView: View {
    @Environment(TourStore.self) private var tour
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if tour.courses.isEmpty {
                    Group {
                        if tour.isLoading { ProgressView().tint(Theme.red) }
                        else { Text(tour.errorMessage ?? "아직 코스가 없어요.").font(.system(size: 13)).foregroundStyle(Theme.gray) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                ForEach(tour.courses) { c in
                    NavigationLink(value: TourView.Route.course(c.id)) { CourseRow(course: c) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .refreshable { await tour.loadCourses() }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(tour.region.map { "\($0) 코스" } ?? "코스 둘러보기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - SEOULLOG SHORTS 배너

private struct HomeShortsBanner: View {
    var onCreate: () -> Void
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.red)
            Circle().stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 260).offset(x: 190, y: 70)
            Circle().stroke(.white.opacity(0.10), lineWidth: 1).frame(width: 200).offset(x: 230, y: 90)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SEOULLOG SHORTS")
                        .font(.system(size: 10, weight: .heavy)).tracking(1)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("서울에서의 순간을\n영상으로!")
                        .font(.system(size: 21, weight: .heavy)).foregroundStyle(.white)
                        .lineSpacing(2).padding(.top, 8)
                    Text("사진만 골라도 나만의 숏폼이 완성돼요.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).padding(.top, 8)
                    Button(action: onCreate) {
                        HStack(spacing: 4) {
                            Text("숏폼 만들기")
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
                Spacer(minLength: 0)
                ZStack {
                    HomePhoneFrame(url: URL(string: "https://picsum.photos/seed/hanok/300/600")!, play: false)
                        .rotationEffect(.degrees(-10)).offset(x: -20, y: -12)
                    HomePhoneFrame(url: URL(string: "https://picsum.photos/seed/palace/300/600")!, play: true)
                        .rotationEffect(.degrees(7)).offset(x: 18, y: 12)
                }
                .frame(width: 130, height: 150)
            }
            .padding(.leading, 20).padding(.trailing, 14).padding(.vertical, 22)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onCreate)
    }
}

private struct HomePhoneFrame: View {
    let url: URL
    let play: Bool
    var body: some View {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.3) }
            .frame(width: 66, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white, lineWidth: 3))
            .overlay {
                if play {
                    Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Circle().fill(.black.opacity(0.35)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
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
