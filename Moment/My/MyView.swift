import SwiftUI
import MapKit
import CoreLocation

/// 마이 탭 — 나만의 기록 (완료한 일정의 발자취 · 내가 만든 V-log)
struct MyView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(CommunityStore.self) private var community
    @Environment(AuthSession.self) private var auth
    @Environment(TourStore.self) private var tour

    @State private var index = 0
    @State private var editing: DiarySummary?
    @State private var deleting: DiarySummary?
    @State private var selectedPost: CommunityPost?
    @State private var actionError: String?
    @State private var pickingCourse = false

    private var completed: [DiarySummary] { diary.diaries.filter { $0.status != "ACTIVE" } }

    var body: some View {
        NavigationStack {
            Group {
                if auth.user == nil { guest } else { content }
            }
            .background(Theme.bg)
            .navigationTitle("나만의 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { deckToolbar } }
        }
        .task { await reload() }
        .sheet(isPresented: $pickingCourse) {
            MyCoursePickerSheet().presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { d in
            MyDiaryEditSheet(summary: d).presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post).presentationDragIndicator(.visible)
        }
        .alert("이 기록을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("삭제", role: .destructive) {
                guard let d = deleting else { return }
                Task {
                    do { try await diary.delete(d.id); index = min(index, max(completed.count - 1, 0)) }
                    catch { actionError = (error as? LocalizedError)?.errorDescription ?? "삭제하지 못했어요." }
                }
            }
            Button("취소", role: .cancel) {}
        } message: { Text("삭제한 기록은 되돌릴 수 없어요.") }
        .alert("알림", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(actionError ?? "") }
    }

    private func reload() async {
        await diary.load()
        await community.loadMine()
        await tour.loadSaved()
    }

    // MARK: 비로그인

    private var guest: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 52)).foregroundStyle(Theme.red.opacity(0.8))
            Text("로그인하면 나만의 기록을 볼 수 있어요")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
            Button { auth.logout() } label: {
                Text("로그인").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 28).frame(height: 44)
                    .background(Capsule().fill(Theme.red))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 본문

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let a = diary.active { activeBanner(a) }
                diaryCard
                MyVlogSection(onOpenPost: { selectedPost = $0 })
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await reload() }
    }

    // MARK: 진행 중 일정

    private func activeBanner(_ a: DiaryDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Theme.red).frame(width: 7, height: 7)
                Text("진행 중인 일정 · \(a.title)")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.red).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(diary.steps.formatted()) 걸음")
                    .font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(MyFormat.distance(diary.distanceMeters)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gray)
                Text("≈\(diary.kcal)kcal").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gray)
                Spacer()
                Button { Task { await diary.finish() } } label: {
                    Group {
                        if diary.isBusy { ProgressView().tint(.white) }
                        else { Text("종료하기").font(.system(size: 13, weight: .bold)) }
                    }
                    .foregroundStyle(.white).frame(width: 78, height: 34)
                    .background(Capsule().fill(Theme.red))
                }
                .disabled(diary.isBusy)
            }
            if let e = diary.tripError {
                Text(e).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.red)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.blueSoft))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.red.opacity(0.25), lineWidth: 1))
    }

    // MARK: 기록 덱 (한 장씩 넘기는 카드 스택)

    @ViewBuilder
    private var diaryCard: some View {
        let list = completed
        if list.isEmpty {
            VStack(spacing: 0) {
                if diary.isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
                else { emptyDiary }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        } else {
            MyDeck(list: list,
                   index: Binding(get: { min(index, list.count - 1) }, set: { index = $0 }),
                   onEdit: { editing = $0 })
            if !diary.isTracking { startTripButton }
        }
    }

    /// 발자취 기록 시작 → 코스 선택 모달 (고르면 바로 기록 시작)
    private var startTripButton: some View {
        Button { pickingCourse = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "shoeprints.fill")
                Text("발자취 기록 시작하기")
            }
            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.red))
        }
        .padding(.horizontal, 0)
        .padding(.top, 4)
    }

    private var current: DiarySummary? {
        let list = completed
        guard !list.isEmpty else { return nil }
        return list[min(index, list.count - 1)]
    }

    @ViewBuilder
    private var deckToolbar: some View {
        if auth.user != nil, let cur = current {
            HStack(spacing: 14) {
                ShareLink(item: MyDeckFormat.shareText(cur, diary.details[cur.id])) {
                    Image(systemName: "square.and.arrow.up")
                }
                Menu {
                    Button { editing = cur } label: { Label("제목·메모 수정", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = cur } label: { Label("기록 삭제", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
        }
    }

    private var emptyDiary: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.blueSoft).frame(width: 96, height: 96)
                Image(systemName: "shoeprints.fill").font(.system(size: 36)).foregroundStyle(Theme.red)
            }
            .padding(.top, 24)
            Text("아직 기록이 없어요").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            Text("코스를 골라 여정을 시작하면 걸음과 발자취가 기록돼요")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gray)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
            Button { pickingCourse = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                    Text("발자취 기록 시작하기")
                }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 24).frame(height: 44)
                .background(Capsule().fill(Theme.red))
            }
            .disabled(diary.isTracking)
            .padding(.top, 4).padding(.bottom, 20)
            if let e = diary.errorMessage {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

}

// MARK: - 기록 덱 (스와이프로 한 장씩 넘김)

private struct MyDeck: View {
    let list: [DiarySummary]
    @Binding var index: Int
    var onEdit: (DiarySummary) -> Void

    @State private var drag: CGFloat = 0
    @State private var horizontal: Bool?

    private var window: [Int] {
        guard !list.isEmpty else { return [] }
        return Array(max(0, index - 1)...min(list.count - 1, index + 2))
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                ForEach(window, id: \.self) { k in
                    let rel = k - index
                    MyDeckCard(summary: list[k], onEdit: { onEdit(list[k]) })
                        .modifier(MyDeckPlacement(pos: position(rel), front: rel == 0, drag: drag))
                        .zIndex(rel == 0 ? 10 : (rel > 0 ? Double(10 - rel) : 8.5))
                        .allowsHitTesting(rel == 0)
                }
            }
            .padding(.leading, 18).padding(.trailing, 40)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)

        }
    }

    /// 덱 안 위치(0 = 맨 앞). 드래그하는 동안 다음/이전 카드가 앞으로 조금씩 나온다
    private func position(_ rel: Int) -> CGFloat {
        let p = min(abs(drag) / 160, 1)
        var pos = CGFloat(rel)
        if drag < 0, rel > 0 { pos -= p }
        if drag > 0, rel < 0 { pos += p }
        return pos
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { v in
                if horizontal == nil { horizontal = abs(v.translation.width) > abs(v.translation.height) }
                guard horizontal == true else { return }
                var w = v.translation.width
                if (w < 0 && index >= list.count - 1) || (w > 0 && index <= 0) { w *= 0.3 }
                drag = 190 * CGFloat(tanh(Double(w) / 190))   // 손가락을 따라가되 끝으로 갈수록 부드럽게 저항
            }
            .onEnded { v in
                let wasHorizontal = horizontal == true
                horizontal = nil
                guard wasHorizontal else { return }
                let w = v.translation.width, pw = v.predictedEndTranslation.width
                if (w < -90 || pw < -260), index < list.count - 1 { fly(next: true) }
                else if (w > 90 || pw > 260), index > 0 { fly(next: false) }
                else { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = 0 } }
            }
    }

    private func fly(next: Bool) {
        let target = index + (next ? 1 : -1)
        guard list.indices.contains(target) else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { drag = 0 }
            return
        }
        // 한 번의 스프링으로 이어서 움직임: 앞 카드는 지금 위치에서 덱 뒤 자리로, 다음 카드는 앞으로
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            index = target
            drag = 0
        }
    }

}

/// 덱 위치에 따른 오프셋·크기·기울기 (앞 카드는 드래그를 따라 3D 로 기운다)
private struct MyDeckPlacement: ViewModifier {
    let pos: CGFloat
    let front: Bool
    let drag: CGFloat

    func body(content: Content) -> some View {
        let a = abs(pos)
        // 뒤 카드가 오른쪽으로 확실히 비껴 보이게 (참고: 카드 스택 영상)
        let x: CGFloat = pos >= 0 ? (pos <= 1 ? 26 * pos : 26 + 18 * (pos - 1)) : 26 * pos
        let tilt = front ? Double(max(-25, min(25, drag / 8))) : 0
        let spin = front ? Double(max(-6, min(6, drag / 40))) : 0
        content
            // 밝은 배경에서도 뒤 카드가 보이도록 살짝 어둡게 + 테두리
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(front ? 0 : 0.035 * Double(min(a, 2)))).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: front ? 0 : 1).allowsHitTesting(false))
            .brightness(-0.04 * Double(a))
            .opacity(a > 2.2 ? 0 : 1 - 0.1 * Double(a))
            .scaleEffect(1 - 0.06 * a, anchor: pos >= 0 ? .trailing : .leading)
            .rotationEffect(.degrees(Double(3.5 * pos) + spin), anchor: .bottom)
            .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(front ? 0.08 : 0.12), radius: front ? 14 : 8, x: 0, y: 4)
            .offset(x: x + (front ? drag : 0))
    }
}

// MARK: - 덱 카드 한 장

private struct MyDeckCard: View {
    let summary: DiarySummary
    var onEdit: () -> Void

    @Environment(DiaryStore.self) private var diary
    @State private var loaded = false

    private var detail: DiaryDetail? { diary.details[summary.id] }
    private var done: Bool { (detail?.status ?? summary.status) == "COMPLETED" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            mapArea

            HStack(alignment: .firstTextBaseline) {
                Text(detail?.title ?? summary.title)
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 8)
                Text(MyDeckFormat.date(summary.recordDate))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gray)
            }

            stats

            VStack(alignment: .leading, spacing: 8) {
                Text("메모").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                // 메모 영역 자체는 탭/스와이프에 반응하지 않고, 연필 버튼만 수정 모달을 연다 (덱 스와이프 방해 X)
                let memo = detail?.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                ZStack(alignment: .topTrailing) {
                    Text(memo.isEmpty ? "오늘의 여정을 기록해 보세요" : memo)
                        .font(.system(size: 14))
                        .foregroundStyle(memo.isEmpty ? Theme.gray.opacity(0.7) : Theme.ink)
                        .lineLimit(4).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                        .padding(.trailing, 30)
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gray)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.7)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 8, y: -8)
                    .accessibilityLabel("메모 수정")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.line.opacity(0.4)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .task(id: summary.id) {
            await diary.detail(summary.id)
            loaded = true
        }
    }

    private var mapArea: some View {
        Group {
            if let d = detail, !d.points.isEmpty {
                MyDeckRouteMap(points: d.points).id(d.points.count)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.blueSoft)
                    .overlay {
                        if !loaded { ProgressView() }
                        else {
                            VStack(spacing: 8) {
                                Image(systemName: "shoeprints.fill").font(.system(size: 30)).foregroundStyle(Theme.red.opacity(0.7))
                                Text("이동 경로가 기록되지 않았어요")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gray)
                            }
                        }
                    }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                Image(systemName: done ? "checkmark.circle.fill" : "record.circle")
                    .foregroundStyle(done ? Color.green : Theme.red)
                Text(done ? "기록 완료" : "기록 중").foregroundStyle(done ? Theme.ink : Theme.red)
            }
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .padding(10)
        }
    }

    private var stats: some View {
        let pts = detail?.points ?? []
        let distance = pts.count > 1 ? MyDeckFormat.distanceParts(MyFormat.length(pts)) : ("-", "")
        return HStack(spacing: 0) {
            stat("shoeprints.fill", "걸음 수", (summary.steps.formatted(), " 걸음"))
            divider
            stat("mappin.and.ellipse", "이동 거리", distance)
            divider
            stat("clock", "이동 시간", (MyDeckFormat.hms(summary), ""))
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.line.opacity(0.4)))
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 34)
    }

    private func stat(_ icon: String, _ label: String, _ value: (String, String)) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.gray)
            (Text(value.0).font(.system(size: 18, weight: .heavy))
             + Text(value.1).font(.system(size: 12, weight: .bold)))
                .foregroundStyle(Theme.red)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

// MARK: - 덱 지도 (경로 · 출발/도착 · 중간 지점)

private struct MyDeckRouteMap: View {
    let points: [DiaryPoint]

    private var coords: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// 중간 지점: 일정 간격으로 최대 6개
    private var mids: [Int] {
        guard points.count > 2 else { return [] }
        let step = max((points.count - 1) / 7, 1)
        return Array(stride(from: step, to: points.count - 1, by: step).prefix(6))
    }

    private var region: MKCoordinateRegion {
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.6, 0.004),
                                   longitudeDelta: max((maxLng - minLng) * 1.6, 0.004)))
    }

    var body: some View {
        let c = coords
        Map(initialPosition: .region(region), interactionModes: []) {
            if c.count > 1 {
                MapPolyline(coordinates: c)
                    .stroke(Theme.red, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(mids, id: \.self) { i in
                Annotation("", coordinate: c[i]) {
                    Circle().fill(.white).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.red, lineWidth: 1.5))
                }
            }
            if let s = c.first {
                Annotation("", coordinate: s) {
                    Circle().fill(Color.green).frame(width: 22, height: 22)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
            }
            if c.count > 1, let e = c.last {
                Annotation("", coordinate: e, anchor: .bottom) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.red)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
    }
}

// MARK: - 썸네일 타일


// MARK: - 덱 포맷

private enum MyDeckFormat {
    /// "2026-11-06" → "2026.11.06"
    static func date(_ s: String) -> String { s.replacingOccurrences(of: "-", with: ".") }

    /// "2026-11-06" → "11.06"
    static func shortDate(_ s: String) -> String {
        let parts = s.split(separator: "-")
        return parts.count == 3 ? "\(parts[1]).\(parts[2])" : s
    }

    static func distanceParts(_ m: Double) -> (String, String) {
        m >= 1000 ? (String(format: "%.1f", m / 1000), " km") : ("\(Int(m.rounded()))", " m")
    }

    static func hms(_ s: DiarySummary) -> String {
        guard let end = s.endedAt else { return "-" }
        let t = max(Int(end.timeIntervalSince(s.startedAt)), 0)
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    static func shareText(_ s: DiarySummary, _ d: DiaryDetail?) -> String {
        let pts = d?.points ?? []
        let km = pts.count > 1 ? distanceParts(MyFormat.length(pts)) : ("-", "")
        return "\(d?.title ?? s.title) · \(date(s.recordDate))\n"
            + "\(s.steps.formatted())걸음 · \(km.0)\(km.1) · \(hms(s))\n#설로그"
    }
}

// MARK: - 제목·메모 수정

private struct MyDiaryEditSheet: View {
    let summary: DiarySummary
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var memo = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("제목") { TextField("제목", text: $title) }
                Section("메모") {
                    TextField("메모를 남겨보세요", text: $memo, axis: .vertical).lineLimit(4...10)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.red) }
            }
            .navigationTitle("기록 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() }
                    else {
                        Button("저장") { save() }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .tint(Theme.red)
        .onAppear {
            let d = diary.details[summary.id]
            title = d?.title ?? summary.title
            memo = d?.memo ?? ""
        }
    }

    private func save() {
        saving = true; error = nil
        Task {
            defer { saving = false }
            do {
                try await diary.update(summary.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), memo: memo)
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "저장하지 못했어요."
            }
        }
    }
}

// MARK: - 포맷

private enum MyFormat {
    static func distance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1fkm", m / 1000) : "\(Int(m.rounded()))m"
    }

    static func duration(_ s: TimeInterval) -> String {
        let mins = max(Int(s / 60), 0)
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }

    static func length(_ pts: [DiaryPoint]) -> Double {
        zip(pts, pts.dropFirst()).reduce(0) { acc, p in
            acc + CLLocation(latitude: p.0.latitude, longitude: p.0.longitude)
                .distance(from: CLLocation(latitude: p.1.latitude, longitude: p.1.longitude))
        }
    }
}


// MARK: - 여정 시작: 코스 선택 모달 (코스를 누르면 바로 발자취 기록 시작)

private struct MyCoursePickerSheet: View {
    @Environment(TourStore.self) private var tour
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0            // 0 저장한 코스, 1 추천 코스
    @State private var chosen: Int64?

    private var list: [CourseSummary] { tab == 0 ? tour.savedCourses : tour.courses }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("어떤 코스로 떠날까요?").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("코스를 누르면 바로 여정이 시작되고 걸음·발자취가 기록돼요")
                    .font(.system(size: 13)).foregroundStyle(Theme.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 24)

            Picker("", selection: $tab) {
                Text("저장한 코스 \(tour.savedCourses.count)").tag(0)
                Text("추천 코스").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20).padding(.vertical, 14)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if list.isEmpty {
                        Text(tab == 0 ? "저장한 코스가 없어요. 추천 코스에서 골라보세요." : "코스를 불러오는 중이에요…")
                            .font(.system(size: 13)).foregroundStyle(Theme.gray).padding(.top, 30)
                    }
                    ForEach(list) { c in
                        Button { start(c) } label: {
                            MyPickerRow(course: c, loading: diary.isBusy && chosen == c.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(diary.isBusy)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
            if let e = diary.tripError {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.bottom, 8)
            }
        }
        .background(Theme.bg)
        .task {
            await tour.loadSaved()
            if tour.courses.isEmpty { await tour.load() }
            if tour.savedCourses.isEmpty { tab = 1 }
        }
    }

    private func start(_ c: CourseSummary) {
        chosen = c.id
        Task {
            await diary.start(courseId: c.id, title: nil)
            if diary.isTracking { dismiss() }
        }
    }
}

private struct MyPickerRow: View {
    let course: CourseSummary
    var loading = false
    var body: some View {
        HStack(spacing: 12) {
            CachedImage(url: CourseFormat.imageURL(course.thumbnailUrl))
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(course.region ?? "서울").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                Text(course.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(course.stopCount)곳 · \(CourseFormat.duration(course.totalMinutes))")
                    .font(.system(size: 12)).foregroundStyle(Theme.gray)
            }
            Spacer(minLength: 0)
            if loading {
                ProgressView().tint(Theme.red)
            } else {
                Text("시작").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(Theme.red))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
