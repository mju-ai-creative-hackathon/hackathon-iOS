import SwiftUI

/// 탭 루트: 여행 도장깨기
struct TourView: View {
    @Environment(AppStore.self) private var store
    @State private var region = "전체"
    private let regions = ["전체", "부산", "제주", "경주"]

    private var filtered: [TravelCourse] {
        region == "전체" ? store.courses : store.courses.filter { $0.region == region }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    chips
                    LazyVStack(spacing: 16) {
                        ForEach(filtered) { course in
                            NavigationLink(value: course.id) {
                                CourseCard(course: course)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if filtered.isEmpty {
                        Text("이 지역 코스는 준비 중이에요")
                            .font(Theme.hand(16)).foregroundStyle(Theme.blue.opacity(0.7))
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                CourseDetailView(courseID: id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("여행 도장깨기").font(Theme.title(28)).foregroundStyle(Theme.blueDeep)
                Text("코스를 돌며 미션 사진을 모아봐요").font(Theme.hand(14)).foregroundStyle(Theme.blue.opacity(0.75))
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "seal.fill")
                Text("\(store.totalStamps)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.blue))
            .foregroundStyle(Theme.paper)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(regions, id: \.self) { r in
                    Button { withAnimation(.spring(duration: 0.25)) { region = r } } label: {
                        Text(r)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(region == r ? Theme.blue : Theme.paper))
                            .overlay(Capsule().strokeBorder(Theme.blue.opacity(region == r ? 0 : 0.3), lineWidth: 1))
                            .foregroundStyle(region == r ? Theme.paper : Theme.blueDeep)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CourseCard: View {
    let course: TravelCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: course.coverURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Rectangle().fill(Theme.blueSoft.opacity(0.5))
                    }
                }
                .frame(height: 150).frame(maxWidth: .infinity).clipped()

                HStack(spacing: 6) {
                    Text(course.region)
                    Text("·")
                    Text(course.estimatedTime)
                }
                .font(Theme.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.paper.opacity(0.92)))
                .foregroundStyle(Theme.blueDeep)
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(course.title).font(Theme.title(20)).foregroundStyle(Theme.blueDeep)
                Text(course.summary).font(Theme.body).foregroundStyle(Theme.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(course.tags, id: \.self) { t in
                        Text("#\(t)").font(Theme.hand(13)).foregroundStyle(Theme.blue)
                    }
                }
                progress
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.paper))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.blue.opacity(0.18), lineWidth: 1))
    }

    private var progress: some View {
        let total = max(course.spots.count, 1)
        let frac = Double(course.stampedCount) / Double(total)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("도장 \(course.stampedCount)/\(course.spots.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.blueDeep)
                Spacer()
                if course.isCompleted {
                    Text("완주! 릴스 만들기")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.blue))
                        .foregroundStyle(Theme.paper)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.blue.opacity(0.15))
                    Capsule().fill(Theme.blue).frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 8)
        }
    }
}
