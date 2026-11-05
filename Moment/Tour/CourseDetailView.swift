import SwiftUI
import MapKit
import PhotosUI
import UIKit

/// 코스 상세 (프리셋 코스 / AI 맞춤 코스 1안·2안·3안)
struct CourseDetailView: View {
    @Environment(TourStore.self) private var tour
    @Environment(AppStore.self) private var store
    @Environment(AuthSession.self) private var auth
    @Environment(DiaryStore.self) private var diary

    private let courseId: Int64?
    @State private var options: [CourseDetail]
    @State private var selected: Int
    @State private var isLoading = false
    @State private var loadError: String?

    @State private var camera: MapCameraPosition = .automatic
    @State private var focusSeq = 1                         // 지도에서 사진으로 보여줄 장소
    @State private var walkRoutes: [String: [CLLocationCoordinate2D]] = [:]   // "코스id-from" → 실제 도보 경로
    @State private var mapExpanded = false
    @State private var refinePrompt = ""
    @State private var refineError: String?
    @FocusState private var refineFocused: Bool
    @State private var savedOverride: [Int64: Bool] = [:]
    @State private var saving = false
    @State private var showLogin = false
    @State private var saveError: String?

    // 일정 기록
    @State private var tripSaved = false
    @State private var confirmCancel = false
    @State private var otherTripInfo = false

    // 미션 촬영
    @State private var cameraMission: CourseMission?
    @State private var albumMission: CourseMission?
    @State private var albumOpen = false
    @State private var albumItem: PhotosPickerItem?

    init(courseId: Int64) {
        self.courseId = courseId
        _options = State(initialValue: [])
        _selected = State(initialValue: 0)
    }

    init(options: [CourseDetail], selected: Int = 0) {
        self.courseId = nil
        _options = State(initialValue: options)
        _selected = State(initialValue: options.indices.contains(selected) ? selected : 0)
    }

    private var course: CourseDetail? { options.indices.contains(selected) ? options[selected] : nil }

    var body: some View {
        Group {
            if let course {
                content(course)
            } else if let loadError {
                errorView(loadError)
            } else {
                ProgressView().tint(Theme.red).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
        .navigationTitle(options.count > 1 ? "맞춤 코스" : "코스")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let course {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { toggleSave(course) } label: {
                        Image(systemName: isSaved(course) ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(Theme.red)
                    }
                    .disabled(saving)
                }
            }
        }
        .task { await loadIfNeeded() }
        .overlay { if tour.isRefining { RecommendingOverlay(title: "AI가 코스를 고치고 있어요") } }
        .alert("코스를 고치지 못했어요", isPresented: Binding(get: { refineError != nil }, set: { if !$0 { refineError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(refineError ?? "") }
        .alert("로그인이 필요해요", isPresented: $showLogin) {
            Button("로그인") { auth.logout() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("코스를 저장하거나 시작하려면 로그인해 주세요.")
        }
        .alert("저장하지 못했어요", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .modifier(TripAlerts(diary: diary, store: store, tripSaved: $tripSaved, confirmCancel: $confirmCancel, otherTripInfo: $otherTripInfo))
        .fullScreenCover(item: $cameraMission) { mission in
            CameraPicker(video: mission.isVideo, maxDuration: Double(mission.durationSec ?? 15)) { media in
                tour.captures[mission.id] = media
                cameraMission = nil
            } onCancel: {
                cameraMission = nil
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $albumOpen, selection: $albumItem,
                      matching: (albumMission?.isVideo ?? false) ? .videos : .images)
        .onChange(of: albumItem) { _, item in
            guard let item, let mission = albumMission else { return }
            albumItem = nil
            Task {
                if let (media, _) = await MediaImport.load(item) {
                    tour.captures[mission.id] = media
                }
                albumMission = nil
            }
        }
    }

    // MARK: 로딩

    private func loadIfNeeded() async {
        guard let courseId, options.isEmpty, !isLoading else { return }
        isLoading = true; loadError = nil
        defer { isLoading = false }
        do {
            options = [try await tour.detail(courseId)]
            selected = 0
            resetCamera()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "코스를 불러오지 못했어요."
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(Theme.gray)
            Text(message).font(.system(size: 14)).foregroundStyle(Theme.gray).multilineTextAlignment(.center)
            Button {
                loadError = nil
                Task { await loadIfNeeded() }
            } label: {
                Text("다시 시도").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 38)
                    .background(Capsule().fill(Theme.red))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 본문

    private func content(_ course: CourseDetail) -> some View {
        // 루트 탭바가 safeAreaInset 이라 하단 버튼은 VStack 으로 쌓아야 탭바에 안 가려짐
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                routeMap(course)
                VStack(alignment: .leading, spacing: 16) {
                    if options.count > 1 { optionCards }
                    courseCard(course)
                    schedule(course)
                    refineBar(course)
                    if !course.missions.isEmpty { missions(course) }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 20)
        }
        .defaultScrollAnchor(.top)
        bottomBar(course)
        }
    }

    // MARK: 코스 수정 요청 (POST /api/courses/{id}/refinements → 새 AI 코스, 원본 유지)

    private func refineBar(_ course: CourseDetail) -> some View {
        let empty = refinePrompt.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.red)
                TextField("이 코스를 이렇게 바꿔줘 (예: 카페 하나 넣어줘)", text: $refinePrompt, axis: .vertical)
                    .lineLimit(1...3).font(.system(size: 14))
                    .focused($refineFocused)
                    .submitLabel(.send)
                    .onSubmit { refine(course) }
                Button { refine(course) } label: {
                    Text("수정").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Capsule().fill(empty ? Theme.line : Theme.red))
                }
                .disabled(empty || tour.isRefining)
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.red.opacity(0.3), lineWidth: 1))
            Text("원래 코스는 그대로 두고, 고친 코스를 새 안으로 추가해요")
                .font(.system(size: 11)).foregroundStyle(Theme.gray).padding(.leading, 4)
        }
    }

    private func refine(_ course: CourseDetail) {
        refineFocused = false
        guard auth.user != nil else { showLogin = true; return }
        let text = refinePrompt
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !tour.isRefining else { return }
        Task {
            do {
                let new = try await tour.refine(course.id, prompt: text)
                refinePrompt = ""
                withAnimation(.snappy) {
                    options.append(new)
                    selected = options.count - 1
                }
                resetCamera()
            } catch {
                refineError = (error as? LocalizedError)?.errorDescription ?? "잠시 후 다시 시도해 주세요."
            }
        }
    }

    // MARK: 지도

    /// 경로 지도: 실제 도보 경로 점선 + 선택한 장소만 사진 핀, 나머지는 작은 번호 점 (겹침 없음)
    private func routeMap(_ course: CourseDetail) -> some View {
        let stops = course.stops.sorted { $0.seq < $1.seq }
        let focus = stops.first { $0.seq == focusSeq } ?? stops.first
        let nextLeg = course.legs.first { $0.fromSeq == focus?.seq }
        return VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Map(position: $camera) {
                    if let origin = course.origin, let first = stops.first {
                        MapPolyline(coordinates: [origin.coordinate, first.coordinate])
                            .stroke(Theme.gray, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [4, 5]))
                    }
                    ForEach(Array(zip(stops, stops.dropFirst())), id: \.0.seq) { a, b in
                        MapPolyline(coordinates: walkRoutes["\(course.id)-\(a.seq)"] ?? [a.coordinate, b.coordinate])
                            .stroke(Theme.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [6, 6]))
                    }
                    ForEach(stops) { stop in
                        Annotation("", coordinate: stop.coordinate, anchor: .center) {
                            Button { withAnimation(.snappy) { focusSeq = stop.seq } } label: {
                                StopDot(seq: stop.seq, on: stop.seq == focus?.seq)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let origin = course.origin {
                        Annotation("", coordinate: origin.coordinate, anchor: .center) {
                            OriginPin(name: origin.name)
                        }
                    }
                    if let focus {
                        Annotation("", coordinate: focus.coordinate, anchor: .bottom) {
                            PhotoPin(url: courseImageURL(focus.imageUrl)).padding(.bottom, 14)
                        }
                    }
                    if let leg = nextLeg, let a = focus, let b = stops.first(where: { $0.seq == leg.toSeq }) {
                        let path = walkRoutes["\(course.id)-\(a.seq)"] ?? [a.coordinate, b.coordinate]
                        Annotation("", coordinate: path[path.count / 2], anchor: .center) {
                            Text("\(leg.mode == "WALK" ? "도보" : "대중교통") \(leg.estMinutes)분")
                                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.red)
                                .shadow(color: .white, radius: 0, x: 1, y: 1).shadow(color: .white, radius: 0, x: -1, y: -1)
                                .shadow(color: .white, radius: 3)
                                .offset(x: 34)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                .mapControlVisibility(.hidden)

                Button { withAnimation(.snappy) { mapExpanded.toggle() } } label: {
                    Image(systemName: mapExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.92)))
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                }
                .padding(10)
            }
            .frame(height: mapExpanded ? 440 : 250)

            if let focus {
                HStack(spacing: 10) {
                    Text("\(focus.seq)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Circle().fill(Theme.red))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(focus.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                        if let addr = focus.address {
                            Text(addr).font(.system(size: 12)).foregroundStyle(Theme.gray).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let leg = nextLeg ?? (focus.seq == stops.first?.seq ? course.startLeg : nil) {
                        Button { openLeg(leg) } label: {
                            Text("다음 장소 길찾기").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red)
                                .padding(.horizontal, 10).frame(height: 28)
                                .background(Capsule().fill(Theme.blueSoft))
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 8)
        .onAppear { resetCamera() }
        .task(id: course.id) { await loadWalkRoutes(course) }
    }

    /// 구간별 실제 도보 경로 (MapKit). 실패하면 직선 유지
    private func loadWalkRoutes(_ course: CourseDetail) async {
        let stops = course.stops.sorted { $0.seq < $1.seq }
        for (a, b) in zip(stops, stops.dropFirst()) {
            let key = "\(course.id)-\(a.seq)"
            guard walkRoutes[key] == nil else { continue }
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: a.coordinate))
            req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.coordinate))
            req.transportType = .walking
            guard let route = try? await MKDirections(request: req).calculate().routes.first else { continue }
            let poly = route.polyline
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: poly.pointCount)
            poly.getCoordinates(&coords, range: NSRange(location: 0, length: poly.pointCount))
            walkRoutes[key] = [a.coordinate] + coords + [b.coordinate]
        }
    }

    private func resetCamera() {
        guard let course else { return }
        focusSeq = course.stops.map(\.seq).min() ?? 1
        camera = .rect(Self.fitRect(course.stops, origin: course.origin))
    }

    private static func fitRect(_ stops: [CourseStop], origin: CourseOrigin? = nil) -> MKMapRect {
        let points = stops.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)) }
            + (origin.map { [MKMapPoint($0.coordinate)] } ?? [])
        guard let first = points.first else { return .world }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for p in points.dropFirst() { rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0))) }
        let minSide = 1500.0   // 한 곳일 때 너무 확대되지 않게
        let w = max(rect.size.width, minSide), h = max(rect.size.height, minSide)
        rect = MKMapRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        return rect.insetBy(dx: -w * 0.3, dy: -h * 0.45)
    }

    // MARK: 1안/2안/3안

    private var optionCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.element.id) { i, opt in
                    let on = i == selected
                    Button {
                        guard !on else { return }
                        selected = i
                        resetCamera()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(i + 1)안").font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(on ? Theme.red : Theme.ink)
                                Spacer()
                                if on {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.red)
                                }
                            }
                            Text(opt.stops.sorted { $0.seq < $1.seq }.map(\.name).joined(separator: " → "))
                                .font(.system(size: 12)).foregroundStyle(Theme.gray)
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                        }
                        .padding(12)
                        .frame(width: 180, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(on ? Theme.red : Theme.line, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 코스 카드

    private func courseCard(_ course: CourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow(course))
                .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                .foregroundStyle(Theme.red)
            Text(course.title).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
            if let s = course.summary, !s.isEmpty {
                Text(s).font(.system(size: 13)).foregroundStyle(Theme.gray)
            }
            HStack(spacing: 0) {
                statColumn("\(course.stopCount)곳", "장소")
                Rectangle().fill(Theme.line).frame(width: 1, height: 32)
                statColumn(Self.duration(course.totalMinutes), "소요 시간")
                Rectangle().fill(Theme.line).frame(width: 1, height: 32)
                statColumn(Self.cost(course.estimatedCost), "예상 비용")
            }
            .padding(.top, 6)
            if let d = course.distanceMeters {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.system(size: 10))
                    Text("내 위치에서 \(Self.distance(d))")
                }
                .font(.system(size: 12)).foregroundStyle(Theme.gray)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .courseCardStyle()
    }

    private func eyebrow(_ course: CourseDetail) -> String {
        if course.source == "AI" {
            return options.count > 1 ? "SEOULLOG 맞춤 코스 \(selected + 1)안" : "SEOULLOG 맞춤 코스"
        }
        if let r = course.region, !r.isEmpty { return "추천 코스 · \(r)" }
        return "추천 코스"
    }

    private func statColumn(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 오늘의 일정

    private func schedule(_ course: CourseDetail) -> some View {
        let stops = course.stops.sorted { $0.seq < $1.seq }
        let dayCount = Set(stops.map(\.dayNo)).count
        let multi = dayCount > 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(multi ? "여행 일정" : "오늘의 일정").font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                Spacer()
                if multi {
                    Text("\(dayCount)일 코스").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                if let start = course.startLeg {
                    CourseLegRow(leg: start, title: "\(startName(start, course)) → \(start.toName ?? stops.first?.name ?? "")") { openLeg(start) }
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                    if multi && (i == 0 || stops[i - 1].dayNo != stop.dayNo) {
                        CourseDayHeader(day: stop.dayNo, startTime: stop.startTime, first: i == 0 && course.startLeg == nil)
                    }
                    CourseStopRow(stop: stop)
                    if i + 1 < stops.count,
                       let leg = course.legs.first(where: { $0.fromSeq == stop.seq && $0.toSeq == stops[i + 1].seq }) {
                        CourseLegRow(leg: leg, title: nil, nextDay: stops[i + 1].dayNo != stop.dayNo) { openLeg(leg) }
                    }
                }
            }
            .padding(14)
            .courseCardStyle()
        }
    }

    // MARK: K-Mission

    private func missions(_ course: CourseDetail) -> some View {
        let stopsBySeq = Dictionary(course.stops.map { ($0.seq, $0) }, uniquingKeysWith: { a, _ in a })
        let groups = Dictionary(grouping: course.missions, by: \.stopSeq).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("K-MISSION").font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(Theme.red))
                Text("촬영 미션").font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(course.missions.count)개").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.gray)
            }
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.red)
                Text("이 코스에서 찍어볼 장면들이에요. 사진·영상을 모으면 AI가 숏폼으로 편집해요")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.blueSoft))

            ForEach(groups, id: \.key) { seq, list in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CourseSeqBadge(seq: seq, size: 20)
                        Text(stopsBySeq[seq]?.name ?? "\(seq)번째 장소")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(list.count)개").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.gray)
                    }
                    .padding(.top, 6)
                    ForEach(Array(list.enumerated()), id: \.element.id) { j, mission in
                        CourseMissionCard(label: "\(seq)-\(j + 1)", mission: mission)
                    }
                }
            }
        }
    }

    // MARK: 하단 바

    private func capturedMissions(_ course: CourseDetail) -> [(CourseMission, MediaItem)] {
        course.missions.compactMap { m in tour.captures[m.id].map { (m, $0) } }
    }

    private func bottomBar(_ course: CourseDetail) -> some View {
        let saved = isSaved(course)
        let trackingThis = diary.active?.courseId == course.id
        return VStack(spacing: 8) {
            if trackingThis, let a = diary.active { tripStats(a.startedAt) }
            HStack(spacing: 10) {
            Button { toggleSave(course) } label: {
                HStack(spacing: 5) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    Text(saved ? "저장됨" : "코스 저장")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.red)
                .padding(.horizontal, 16).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.red.opacity(0.5), lineWidth: 1))
            }
            .disabled(saving)

            Button {
                if let leg = course.startLeg ?? course.legs.first { openLeg(leg) }
            } label: {
                Image(systemName: "map.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.red.opacity(0.5), lineWidth: 1))
            }
            .accessibilityLabel("지도에서 보기")

            tripButton(course)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background(Theme.bg.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) })
    }

    private func tripStats(_ startedAt: Date) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.red).frame(width: 7, height: 7)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let km = String(format: "%.2fkm", diary.distanceMeters / 1000)
                Text("\(diary.steps) 걸음 · \(km) · ≈\(diary.kcal)kcal · 경과 \(Self.elapsed(from: startedAt, to: ctx.date))")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Button("취소") { confirmCancel = true }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gray)
                .disabled(diary.isBusy)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(Capsule().fill(Theme.blueSoft))
    }

    @ViewBuilder
    private func tripButton(_ course: CourseDetail) -> some View {
        let active = diary.active
        if active == nil || active?.courseId == course.id {
            let tracking = active != nil
            Button {
                guard auth.user != nil else { showLogin = true; return }
                Task {
                    if tracking {
                        if await diary.finish() != nil { tripSaved = true }
                    } else {
                        await diary.start(courseId: course.id, title: nil)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if diary.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: tracking ? "stop.circle.fill" : "figure.walk")
                        Text(tracking ? "기록 종료하기" : "코스 시작하기")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.red))
            }
            .disabled(diary.isBusy)
        } else {
            Button { otherTripInfo = true } label: {
                Text("다른 코스 일정 진행 중")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.gray)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.line))
            }
        }
    }

    // MARK: 동작

    private func startName(_ leg: CourseLeg, _ course: CourseDetail) -> String {
        if let n = leg.fromName, !n.isEmpty { return n }
        return course.origin?.name ?? "내 위치"
    }

    private func isSaved(_ course: CourseDetail) -> Bool { savedOverride[course.id] ?? course.saved }

    private func toggleSave(_ course: CourseDetail) {
        guard auth.user != nil else { showLogin = true; return }
        guard !saving else { return }
        let target = !isSaved(course)
        saving = true
        savedOverride[course.id] = target
        Task {
            defer { saving = false }
            do {
                savedOverride[course.id] = try await tour.setSaved(course.id, target)
            } catch {
                savedOverride[course.id] = !target
                saveError = (error as? LocalizedError)?.errorDescription ?? "잠시 후 다시 시도해 주세요."
            }
        }
    }

    private func openLeg(_ leg: CourseLeg) {
        let naver = leg.naverMapUrl.flatMap(URL.init(string:))
        let google = leg.googleMapsUrl.flatMap(URL.init(string:))
        if let naver, UIApplication.shared.canOpenURL(naver) {
            UIApplication.shared.open(naver)
        } else if let google {
            UIApplication.shared.open(google)
        }
    }

    // MARK: 포맷

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)분" }
        return m == 0 ? "\(h)시간" : "\(h)시간 \(m)분"
    }

    static func cost(_ won: Int?) -> String {
        guard let won else { return "-" }
        if won == 0 { return "무료" }
        let f = NumberFormatter(); f.numberStyle = .decimal
        return "₩" + (f.string(from: NSNumber(value: won)) ?? "\(won)")
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let sec = max(0, Int(now.timeIntervalSince(start)))
        let h = sec / 3600, m = (sec % 3600) / 60, s = sec % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func distance(_ meters: Int) -> String {
        meters < 1000 ? "\(meters)m" : String(format: "%.1fkm", Double(meters) / 1000)
    }
}

// MARK: - 하위 뷰

/// 일정 기록 관련 알림 (body 타입 체크 부담을 덜려고 분리)
private struct TripAlerts: ViewModifier {
    let diary: DiaryStore
    let store: AppStore
    @Binding var tripSaved: Bool
    @Binding var confirmCancel: Bool
    @Binding var otherTripInfo: Bool

    func body(content: Content) -> some View {
        content
            .alert("기록을 저장했어요", isPresented: $tripSaved) {
                Button("마이에서 보기") { store.selectedTab = .tour }
                Button("확인", role: .cancel) {}
            } message: {
                Text("오늘의 걸음과 발자취를 마이 탭에서 볼 수 있어요.")
            }
            .alert("기록을 취소할까요?", isPresented: $confirmCancel) {
                Button("기록 취소", role: .destructive) { Task { await diary.cancel() } }
                Button("계속 기록", role: .cancel) {}
            } message: {
                Text("지금까지 모은 걸음수와 경로가 저장되지 않아요.")
            }
            .alert("다른 코스 일정 진행 중", isPresented: $otherTripInfo) {
                Button("마이에서 보기") { store.selectedTab = .tour }
                Button("확인", role: .cancel) {}
            } message: {
                Text("\(diary.active?.courseTitle ?? "다른 코스") 일정을 기록하고 있어요. 마이 탭에서 먼저 종료해 주세요.")
            }
            .alert("일정 기록", isPresented: Binding(get: { diary.tripError != nil }, set: { if !$0 { diary.tripError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(diary.tripError ?? "")
            }
    }
}

private extension View {
    func courseCardStyle() -> some View {
        background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

private struct CourseSeqBadge: View {
    let seq: Int
    var size: CGFloat = 24
    var body: some View {
        Text("\(seq)")
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.red))
    }
}

private func courseImageURL(_ s: String?) -> URL? {
    guard let s, !s.isEmpty else { return nil }
    return URL(string: s).flatMap { $0.scheme == nil ? nil : $0 } ?? APIClient.shared.absolute(s)
}

private struct CourseStopRow: View {
    let stop: CourseStop

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CourseSeqBadge(seq: stop.seq).padding(.top, 2)
            AsyncImage(url: courseImageURL(stop.imageUrl)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Theme.cream.overlay(Image(systemName: "photo").foregroundStyle(Theme.line))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(timeLine).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.red)
                Text(stop.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                if let d = stop.description, !d.isEmpty {
                    Text(d).font(.system(size: 12)).foregroundStyle(Theme.gray).lineLimit(2)
                }
                if let a = stop.address, !a.isEmpty {
                    Text(a).font(.system(size: 10)).foregroundStyle(Theme.gray.opacity(0.8)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var timeLine: String {
        let stay = "\(CourseDetailView.duration(stop.stayMinutes)) 머물기"
        if let t = stop.startTime, !t.isEmpty { return "\(t.prefix(5)) · \(stay)" }
        return stay
    }
}

private struct CourseLegRow: View {
    let leg: CourseLeg
    let title: String?
    var nextDay = false
    let onRoute: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 세로 점선 연결선 (번호 원 중앙에 맞춤)
            Rectangle().fill(.clear).frame(width: 24)
                .overlay(DashedVDivider(color: Theme.red.opacity(0.45)))
            Image(systemName: leg.mode == "PUBLIC" ? "tram.fill" : "figure.walk")
                .font(.system(size: 12)).foregroundStyle(Theme.gray)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                if let title {
                    Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Text(summary).font(.system(size: 12)).foregroundStyle(Theme.gray)
            }
            Spacer(minLength: 4)
            if leg.naverMapUrl != nil || leg.googleMapsUrl != nil {
                Button(action: onRoute) {
                    Text("길찾기").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                        .padding(.horizontal, 10).frame(height: 24)
                        .overlay(Capsule().strokeBorder(Theme.red.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 38)
        .padding(.vertical, 2)
    }

    private var summary: String {
        let mode = leg.mode == "PUBLIC" ? "대중교통" : "도보"
        let text = "\(mode) \(CourseDetailView.duration(leg.estMinutes)) · \(CourseDetailView.distance(leg.distanceMeters))"
        return nextDay ? "다음 날 이동 · \(text)" : text
    }
}

/// 일차 헤더 (숙박 일정)
private struct CourseDayHeader: View {
    let day: Int
    let startTime: String?
    let first: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(day)일차").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(Theme.red))
            if let t = startTime, !t.isEmpty {
                Text("\(t.prefix(5)) 출발").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gray)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .padding(.top, first ? 0 : 10).padding(.bottom, 4)
    }
}

private struct CourseMissionCard: View {
    let label: String
    let mission: CourseMission
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.red)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Capsule().fill(Theme.blueSoft))
                    Image(systemName: mission.isVideo ? "video.fill" : "camera.fill")
                        .font(.system(size: 10)).foregroundStyle(Theme.red)
                    Text(mission.isVideo ? "영상 \(mission.durationSec ?? 15)초" : "사진")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.red)
                }
                Text(mission.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let g = mission.guide, !g.isEmpty {
                    Text(g).font(.system(size: 12)).foregroundStyle(Theme.gray)
                        .lineLimit(expanded ? nil : 2)
                    if g.count > 50 {
                        Button(expanded ? "접기" : "더보기") { withAnimation(.snappy) { expanded.toggle() } }
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.gray)
                            .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            // 추천 화면에서는 미션 소개만 (수행 X)
            Image(systemName: mission.isVideo ? "video" : "camera")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.red.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.blueSoft))
        }
        .padding(12)
        .courseCardStyle()
    }
}

/// 미션 스탬프: 미완료 = 점선 원, 완료 = 사진이 찍힌 도장
private struct CourseStamp: View {
    let image: UIImage?
    let captured: Bool
    let isVideo: Bool
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            if captured {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.blueSoft.overlay(Image(systemName: isVideo ? "video.fill" : "photo").foregroundStyle(Theme.red))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.red, lineWidth: 3))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(.white, Theme.red)
                        .background(Circle().fill(.white).padding(2))
                        .offset(x: 4, y: 4)
                }
                .rotationEffect(.degrees(-8))
            } else {
                Circle()
                    .strokeBorder(Theme.red.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: size, height: size)
                Text("SEOUL\nLOG")
                    .font(.system(size: size * 0.16, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.red.opacity(0.55))
                    .rotationEffect(.degrees(-12))
            }
        }
        .frame(width: size + 6, height: size + 6)
        .animation(.spring(duration: 0.3), value: captured)
    }
}

extension CourseStop {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

extension CourseOrigin {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// 출발지 핀 (진한 원 + '출발' 라벨)
private struct OriginPin: View {
    let name: String
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: "flag.fill").font(.system(size: 8, weight: .bold))
                Text("출발").font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill(Theme.ink))
            Circle().fill(Theme.ink).frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .offset(y: -12)
        .accessibilityLabel("출발지 \(name)")
        .allowsHitTesting(false)
    }
}

/// 작은 번호 점 (선택되면 빨강 채움)
private struct StopDot: View {
    let seq: Int
    let on: Bool
    var body: some View {
        Text("\(seq)").font(.system(size: 10, weight: .heavy))
            .foregroundStyle(on ? .white : Theme.red)
            .frame(width: 20, height: 20)
            .background(Circle().fill(on ? Theme.red : .white))
            .overlay(Circle().strokeBorder(Theme.red, lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .padding(8)            // 탭 영역
            .contentShape(Circle())
    }
}

/// 선택한 장소 사진 핀 (흰 테두리 + 꼬리)
private struct PhotoPin: View {
    let url: URL?
    var body: some View {
        VStack(spacing: 0) {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFill() } else { Theme.cream }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            Triangle().fill(.white).frame(width: 12, height: 7)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .allowsHitTesting(false)
    }
    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
        }
    }
}
