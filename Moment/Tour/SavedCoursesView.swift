import SwiftUI

/// 저장한 코스 목록 (TourView 의 NavigationStack 에서 push)
struct SavedCoursesView: View {
    var onOpen: (Int64) -> Void

    @Environment(TourStore.self) private var tour
    @Environment(AuthSession.self) private var auth

    @State private var query = ""
    @State private var chip: SavedChip = .all
    @State private var pendingUnsave: CourseSummary?
    @State private var errorMessage: String?

    private var filtered: [CourseSummary] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return tour.savedCourses.filter { c in
            guard chip.matches(c) else { return false }
            guard !q.isEmpty else { return true }
            let hay = ([c.title, c.summary ?? "", c.region ?? ""] + c.stopNames).joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    var body: some View {
        Group {
            if auth.user == nil {
                loginPrompt
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SavedHeroCard(count: tour.savedCourses.count)
                        searchField
                        chips
                        HStack {
                            Text("저장한 추천 코스").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(filtered.count)개").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                        }
                        .padding(.top, 4)
                        content
                    }
                    .padding(16)
                }
                .refreshable { await tour.loadSaved() }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("저장한 코스")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .frame(width: 36, height: 36)
                    .background(Theme.blueSoft, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .task { await tour.loadSaved() }
        .alert("저장을 해제할까요?", isPresented: Binding(
            get: { pendingUnsave != nil },
            set: { if !$0 { pendingUnsave = nil } }
        ), presenting: pendingUnsave) { course in
            Button("취소", role: .cancel) { pendingUnsave = nil }
            Button("해제", role: .destructive) {
                pendingUnsave = nil
                Task {
                    do { _ = try await tour.setSaved(course.id, false) }
                    catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "저장 해제에 실패했어요." }
                }
            }
        } message: { course in
            Text("'\(course.title)' 코스가 저장 목록에서 빠져요.")
        }
        .alert("알림", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: 구성 요소

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.gray)
            TextField("코스나 장소를 검색해 보세요", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.gray)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SavedChip.allCases, id: \.self) { c in
                    let on = c == chip
                    Button { chip = c } label: {
                        Text(c.rawValue)
                            .font(.system(size: 13, weight: on ? .bold : .medium))
                            .foregroundStyle(on ? Color.white : Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(on ? Theme.red : Color.white, in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.clear : Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if tour.savedCourses.isEmpty {
            SavedEmptyCard(icon: "bookmark",
                           title: "아직 저장한 코스가 없어요",
                           message: "홈에서 마음에 드는 코스의 북마크를 눌러 저장해 보세요")
        } else if filtered.isEmpty {
            SavedEmptyCard(icon: "magnifyingglass",
                           title: "조건에 맞는 코스가 없어요",
                           message: "다른 검색어나 필터를 골라 보세요")
        } else {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { c in
                    SavedCourseRow(course: c,
                                   onTap: { onOpen(c.id) },
                                   onUnsave: { pendingUnsave = c })
                }
            }
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.red)
                .frame(width: 64, height: 64)
                .background(Theme.blueSoft, in: Circle())
            Text("로그인하면 저장한 코스를 볼 수 있어요")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Button { auth.logout() } label: {
                Text("로그인")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .background(Theme.red, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - 필터

private enum SavedChip: String, CaseIterable {
    case all = "전체", half = "반나절", day = "하루", night = "야경", nature = "자연"

    static let nightWords = ["야경", "밤", "야간", "노을"]
    static let natureWords = ["숲", "공원", "산", "한강", "자연", "정원"]

    private static func has(_ c: CourseSummary, _ words: [String]) -> Bool {
        let text = c.title + " " + (c.summary ?? "")
        return words.contains { text.contains($0) }
    }

    func matches(_ c: CourseSummary) -> Bool {
        switch self {
        case .all: true
        case .half: c.totalMinutes <= 300
        case .day: c.totalMinutes > 300
        case .night: Self.has(c, Self.nightWords)
        case .nature: Self.has(c, Self.natureWords)
        }
    }

    /// 행에 표시할 대표 태그
    static func primary(_ c: CourseSummary) -> SavedChip {
        if has(c, nightWords) { return .night }
        if has(c, natureWords) { return .nature }
        return c.totalMinutes <= 300 ? .half : .day
    }
}

// MARK: - 히어로

private struct SavedHeroCard: View {
    let count: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.red, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("MY SEOUL ROUTES")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Theme.red)
                Text("다시 떠나고 싶은 서울")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("마음에 들었던 추천 코스를 한곳에 모았어요.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.gray)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.red)
                .frame(width: 44, height: 44)
                .background(Color.white, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [.white, Theme.cream.opacity(0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .stroke(Theme.red.opacity(0.07), lineWidth: 1)
                            .frame(width: CGFloat(80 + i * 50), height: CGFloat(80 + i * 50))
                    }
                }
                .offset(x: 70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

// MARK: - 행

private struct SavedCourseRow: View {
    let course: CourseSummary
    var onTap: () -> Void
    var onUnsave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedImage(url: CourseFormat.imageURL(course.thumbnailUrl))
                .frame(width: 88, height: 88)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(SavedChip.primary(course).rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.line.opacity(0.5), in: Capsule())
                Text(course.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(course.stopNames.joined(separator: " → "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.gray)
                    .lineLimit(1)
                Text("\(CourseFormat.duration(course.totalMinutes))  ·  약 \(CourseFormat.cost(course.estimatedCost))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUnsave) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .frame(width: 32, height: 32)
                    .background(Theme.blueSoft, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("저장 해제")
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onTap)
    }
}

// MARK: - 빈 상태

private struct SavedEmptyCard: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.red)
                .frame(width: 56, height: 56)
                .background(Theme.blueSoft, in: Circle())
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
}
