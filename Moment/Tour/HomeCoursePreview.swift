import SwiftUI

/// 홈 "서울에서 뭐 하지?" — 1안/2안/3안 탭 + 선택 코스 미리보기 카드
struct HomeCoursePreview: View {
    let courses: [CourseSummary]
    var badge: String = "맞춤 코스"
    var onOpen: (Int64) -> Void

    @Environment(TourStore.self) private var tour
    @State private var selected = 0
    @State private var details: [Int64: CourseDetail] = [:]
    @State private var failed: Set<Int64> = []

    private var options: [CourseSummary] { Array(courses.prefix(3)) }

    var body: some View {
        if options.isEmpty {
            EmptyView()
        } else {
            let idx = min(selected, options.count - 1)
            let course = options[idx]
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { i, c in
                        HomePreviewOptionTab(n: i + 1, names: c.stopNames, isSelected: i == idx)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selected = i }
                            }
                    }
                }
                HomePreviewFeatured(
                    course: course, n: idx + 1, badge: badge,
                    detail: details[course.id], loadFailed: failed.contains(course.id),
                    onOpen: { onOpen(course.id) }
                )
                .id(course.id)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .animation(.easeInOut(duration: 0.25), value: course.id)
            .task(id: course.id) { await load(course.id) }
        }
    }

    private func load(_ id: Int64) async {
        guard details[id] == nil else { return }
        failed.remove(id)
        do {
            let d = try await tour.detail(id)
            withAnimation(.easeOut(duration: 0.2)) { details[id] = d }
        } catch {
            if !Task.isCancelled { failed.insert(id) }
        }
    }
}

// MARK: - 옵션 탭

private struct HomePreviewOptionTab: View {
    let n: Int
    let names: [String]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("\(n)안")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.red : Theme.ink)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.red)
                }
            }
            Text(names.joined(separator: " → "))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.gray)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Theme.blueSoft.opacity(0.6) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.red : Theme.line, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 대표 카드

private struct HomePreviewFeatured: View {
    let course: CourseSummary
    let n: Int
    let badge: String
    let detail: CourseDetail?
    let loadFailed: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 16) {
                stats
                if let detail {
                    HomePreviewTimeline(stops: detail.stops)
                    if !detail.missions.isEmpty {
                        HomePreviewMissionBox(missions: detail.missions)
                    }
                } else if loadFailed {
                    Text("코스 정보를 불러오지 못했어요")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    HomePreviewSkeleton()
                }
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Text("\(n)안 코스 자세히 보기")
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.red))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.cream
                .overlay { CachedImage(url: CourseFormat.imageURL(course.thumbnailUrl)) }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(badge) \(n)안")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(course.title)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(course.stopNames.joined(separator: " → "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(16)
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Text("\(course.stopCount) SPOTS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.2)))
                .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
                .padding(12)
        }
        .clipped()
    }

    private var costText: String {
        guard let c = course.estimatedCost else { return "-" }
        return c == 0 ? "무료" : "약 " + CourseFormat.cost(c)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            HomePreviewStat(value: "\(course.stopCount)곳", label: "방문 장소")
            Rectangle().fill(Theme.line).frame(width: 1, height: 28)
            HomePreviewStat(value: CourseFormat.duration(course.totalMinutes), label: "예상 시간")
            Rectangle().fill(Theme.line).frame(width: 1, height: 28)
            HomePreviewStat(value: costText, label: "예상 비용")
        }
    }
}

private struct HomePreviewStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 타임라인

private struct HomePreviewTimeline: View {
    let stops: [CourseStop]
    private let maxRows = 4

    var body: some View {
        let sorted = stops.sorted { $0.seq < $1.seq }
        let shown = Array(sorted.prefix(maxRows))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, stop in
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        // 세로 연결선
                        VStack(spacing: 0) {
                            Rectangle().fill(i == 0 ? .clear : Theme.line).frame(width: 2)
                            Rectangle().fill(i == shown.count - 1 ? .clear : Theme.line).frame(width: 2)
                        }
                        Circle().fill(Theme.red).frame(width: 20, height: 20)
                            .overlay(Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                    }
                    .frame(width: 20)
                    CachedImage(url: CourseFormat.imageURL(stop.imageUrl))
                        .frame(width: 44, height: 44)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        if let t = stop.startTime, !t.isEmpty {
                            Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.red)
                        }
                        Text(stop.name).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 56)
            }
            if sorted.count > maxRows {
                Text("+\(sorted.count - maxRows)곳 더")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.gray)
                    .padding(.leading, 32)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - K-MISSION

private struct HomePreviewMissionBox: View {
    let missions: [CourseMission]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("K-MISSION")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.red))
                Text("코스따라 한국 문화 미션 \(missions.count)개")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(missions.prefix(4)) { m in
                        HStack(spacing: 4) {
                            Image(systemName: m.isVideo ? "video.fill" : "camera.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.red)
                            Text(m.title).lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cream))
    }
}

// MARK: - 로딩 스켈레톤

private struct HomePreviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(Theme.line).frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 8).fill(Theme.line.opacity(0.6)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.line.opacity(0.6)).frame(width: 40, height: 8)
                        RoundedRectangle(cornerRadius: 3).fill(Theme.line.opacity(0.6)).frame(width: 140, height: 12)
                    }
                }
            }
        }
        .overlay { ProgressView().tint(Theme.red) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
