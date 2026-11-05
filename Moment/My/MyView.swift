import SwiftUI
import MapKit
import CoreLocation

/// 마이 탭 — 나만의 기록 (완료한 일정의 발자취 · 내가 만든 V-log)
struct MyView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(CommunityStore.self) private var community
    @Environment(AppStore.self) private var store
    @Environment(AuthSession.self) private var auth

    @State private var index = 0
    @State private var editing: DiarySummary?
    @State private var deleting: DiarySummary?
    @State private var selectedPost: CommunityPost?
    @State private var actionError: String?

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
        }
        .task { await reload() }
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
                vlogSection
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

    // MARK: 기록 카드 (캐러셀)

    @ViewBuilder
    private var diaryCard: some View {
        let list = completed
        VStack(spacing: 0) {
            if list.isEmpty {
                if diary.isLoading { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
                else { emptyDiary }
            } else {
                let i = min(index, list.count - 1)
                ZStack {
                    MyDiaryPage(summary: list[i],
                                onEdit: { editing = list[i] },
                                onDelete: { deleting = list[i] })
                        .id(list[i].id)
                        .transition(.opacity)
                    HStack {
                        arrow("chevron.left", enabled: i > 0) { index = i - 1 }
                        Spacer()
                        arrow("chevron.right", enabled: i < list.count - 1) { index = i + 1 }
                    }
                    .padding(.horizontal, 2)
                    .offset(y: -95)
                }
                .animation(.easeInOut(duration: 0.2), value: i)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    if v.translation.width < -40, i < list.count - 1 { index = i + 1 }
                    if v.translation.width > 40, i > 0 { index = i - 1 }
                })
                if list.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<min(list.count, 10), id: \.self) { k in
                            Capsule().fill(k == i ? Theme.red : Theme.line)
                                .frame(width: k == i ? 14 : 6, height: 6)
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? Theme.ink : Theme.gray.opacity(0.4))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.92)))
                .shadow(color: .black.opacity(enabled ? 0.12 : 0), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0)
    }

    private var emptyDiary: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.blueSoft).frame(width: 96, height: 96)
                Image(systemName: "shoeprints.fill").font(.system(size: 36)).foregroundStyle(Theme.red)
            }
            .padding(.top, 24)
            Text("아직 기록이 없어요").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            Text("홈에서 코스를 고르고 '코스 시작하기'를 눌러 발자취를 남겨보세요")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gray)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
            Button { store.selectedTab = .home } label: {
                Text("코스 둘러보기").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).frame(height: 44)
                    .background(Capsule().fill(Theme.red))
            }
            .padding(.top, 4).padding(.bottom, 20)
            if let e = diary.errorMessage {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 내가 만든 V-log

    private var vlogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("내가 만든 V-log").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.ink)
            if community.myPosts.isEmpty {
                VStack(spacing: 10) {
                    Text("아직 만든 V-log가 없어요").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gray)
                    Button { store.selectedTab = .create } label: {
                        Text("숏폼 만들기").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                            .padding(.horizontal, 16).frame(height: 34)
                            .background(Capsule().fill(Theme.blueSoft))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(community.myPosts) { post in
                            MyVlogCard(post: post, saved: community.saved.contains(post.id),
                                       onSave: { community.toggleSaved(post.id) })
                                .onTapGesture { selectedPost = post }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
        }
    }
}

// MARK: - 기록 한 장

private struct MyDiaryPage: View {
    let summary: DiarySummary
    var onEdit: () -> Void
    var onDelete: () -> Void

    @Environment(DiaryStore.self) private var diary
    @State private var loaded = false

    private var detail: DiaryDetail? { diary.details[summary.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let d = detail, !d.points.isEmpty {
                        MyFootprintMap(points: d.points).id(d.points.count)
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
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Menu {
                    Button { onEdit() } label: { Label("제목·메모 수정", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete() } label: { Label("삭제", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.92)))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                }
                .padding(10)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(detail?.title ?? summary.title)
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                Spacer(minLength: 8)
                Text(summary.recordDate.replacingOccurrences(of: "-", with: "."))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("걸음수").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(summary.steps.formatted()) 걸음")
                        .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.red)
                }
                Text(statsLine).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gray)
            }

            Divider().overlay(Theme.line)

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("메모").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gray)
                    }
                    let memo = detail?.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Text(memo.isEmpty ? "메모를 남겨보세요" : memo)
                        .font(.system(size: 14)).foregroundStyle(memo.isEmpty ? Theme.gray.opacity(0.7) : Theme.ink)
                        .lineLimit(4).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .task(id: summary.id) {
            await diary.detail(summary.id)
            loaded = true
        }
    }

    private var statsLine: String {
        var parts: [String] = []
        if let end = summary.endedAt { parts.append(MyFormat.duration(end.timeIntervalSince(summary.startedAt))) }
        if let pts = detail?.points, pts.count > 1 { parts.append(MyFormat.distance(MyFormat.length(pts))) }
        parts.append("≈\(Int((Double(summary.steps) * 0.04).rounded()))kcal")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 발자취 지도

private struct MyFootprintMap: View {
    let points: [DiaryPoint]

    private var coords: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var region: MKCoordinateRegion {
        let lats = points.map(\.latitude), lngs = points.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.004),
                                   longitudeDelta: max((maxLng - minLng) * 1.5, 0.004)))
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords)
                    .stroke(Theme.red, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let s = coords.first {
                Annotation("", coordinate: s) { dot(.green) }
            }
            if coords.count > 1, let e = coords.last {
                Annotation("", coordinate: e) { dot(Theme.red) }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
    }

    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
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

// MARK: - V-log 카드

private struct MyVlogCard: View {
    let post: CommunityPost
    var saved = false
    var onSave: () -> Void = {}

    var body: some View {
        Color(Theme.cream)
            .frame(width: 120, height: 170)
            .overlay {
                ZStack {
                    CachedImage(url: APIClient.shared.absolute(post.thumbnailUrl))
                    LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("SHORTS").font(.system(size: 7, weight: .heavy)).tracking(0.5).foregroundStyle(.white)
                    .padding(.horizontal, 5).frame(height: 15)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
                    .padding(7)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onSave) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.black.opacity(0.28)))
                }
                .buttonStyle(.plain)
                .padding(5)
            }
            .overlay {
                if post.media.first?.isVideo == true {
                    Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.black.opacity(0.3)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2))
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(post.author.name)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    Text(post.title).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    if !post.tags.isEmpty {
                        Text(post.tags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
