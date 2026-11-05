import SwiftUI
import MapKit

struct CourseDetailView: View {
    let courseID: UUID
    @Environment(AppStore.self) private var store
    @State private var missionSpot: TourSpot?
    @State private var showReel = false

    var body: some View {
        Group {
            if let course = store.course(courseID) {
                content(course)
            } else {
                Text("코스를 찾을 수 없어요").font(Theme.hand(16))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func content(_ course: TravelCourse) -> some View {
        let nextID = course.spots.first(where: { !$0.isStamped })?.id
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                mapView(course)
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.title).font(Theme.title(24)).foregroundStyle(Theme.blueDeep)
                    Text(course.summary).font(Theme.body).foregroundStyle(Theme.ink.opacity(0.7))
                }
                .padding(.horizontal, 16)

                Text("로드맵").font(Theme.hand(22)).foregroundStyle(Theme.blue)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(Array(course.spots.enumerated()), id: \.element.id) { idx, spot in
                        RoadmapRow(index: idx + 1, spot: spot,
                                   isNext: spot.id == nextID,
                                   isLast: idx == course.spots.count - 1) {
                            missionSpot = spot
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(course) }
        .sheet(item: $missionSpot) { spot in
            SpotMissionView(courseID: course.id, spotID: spot.id)
        }
        .fullScreenCover(isPresented: $showReel) {
            ReelGenerationView(
                request: ReelGenerationRequest(
                    source: .tour(courseID: course.id),
                    media: course.spots.compactMap(\.capturedPhoto).map { MediaItem(kind: .photo($0)) },
                    style: .cinematic,
                    caption: "\(course.title) 완주 🏁"),
                onDone: { showReel = false })
        }
    }

    // MARK: Map

    private func mapView(_ course: TravelCourse) -> some View {
        let coords = course.spots.map(\.coordinate)
        return Map(initialPosition: .region(region(for: coords))) {
            MapPolyline(coordinates: coords)
                .stroke(Theme.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            ForEach(Array(course.spots.enumerated()), id: \.element.id) { idx, spot in
                Annotation("", coordinate: spot.coordinate) {
                    ZStack {
                        Circle().fill(spot.isStamped ? Theme.blue : Theme.paper)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                        if spot.isStamped {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.paper)
                        } else {
                            Text("\(idx + 1)").font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                }
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.blue.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coords.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 36.5, longitude: 127.8),
                                      span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.02),
                                    longitudeDelta: max((maxLng - minLng) * 1.5, 0.02))
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: Bottom bar

    private func bottomBar(_ course: TravelCourse) -> some View {
        let total = course.spots.count
        let remain = total - course.stampedCount
        return VStack(spacing: 10) {
            HStack {
                Text("진행률 \(course.stampedCount)/\(total)")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.blueDeep)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.blue.opacity(0.15))
                        Capsule().fill(Theme.blue)
                            .frame(width: geo.size.width * Double(course.stampedCount) / Double(max(total, 1)))
                    }
                }
                .frame(height: 8)
            }
            Button { showReel = true } label: {
                Text("도장깨기 릴스 만들기 ✨")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!course.isCompleted)
            .opacity(course.isCompleted ? 1 : 0.4)
            if !course.isCompleted {
                Text("\(remain)곳 더 찍으면 릴스가 완성돼요")
                    .font(Theme.hand(14)).foregroundStyle(Theme.blue)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12)
        .padding(.bottom, 96)
        .background(
            Rectangle().fill(Theme.cream.opacity(0.96))
                .shadow(color: Theme.blue.opacity(0.12), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - 로드맵 한 줄

private struct RoadmapRow: View {
    let index: Int
    let spot: TourSpot
    let isNext: Bool
    let isLast: Bool
    var onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(spot.isStamped || isNext ? Theme.blue : Theme.paper)
                        .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                    if spot.isStamped {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.paper)
                    } else {
                        Text("\(index)").font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(isNext ? Theme.paper : Theme.blue)
                    }
                }
                .frame(width: 34, height: 34)
                if !isLast {
                    DashedVDivider(color: Theme.blue.opacity(0.5)).frame(maxHeight: .infinity)
                }
            }
            Button(action: onTap) { card }
                .buttonStyle(.plain)
                .padding(.bottom, isLast ? 0 : 16)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isNext {
                Text("다음 차례!").font(Theme.hand(14)).foregroundStyle(Theme.red)
            }
            AsyncImage(url: spot.previewURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Rectangle().fill(Theme.blueSoft.opacity(0.4))
                }
            }
            .frame(height: 120).frame(maxWidth: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(spot.name).font(Theme.title(18)).foregroundStyle(Theme.blueDeep)
            Text(spot.description).font(Theme.body).foregroundStyle(Theme.ink.opacity(0.7))
            Text("📸 \(spot.mission)")
                .font(Theme.hand(15)).foregroundStyle(Theme.blue)
                .fixedSize(horizontal: false, vertical: true)

            if let photo = spot.capturedPhoto {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(height: 110).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    StampMark(size: 72).padding(8)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                    Text(isNext ? "지금 도장 찍으러 가기" : "도장 찍기")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.blue)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(isNext ? Theme.blue : Theme.blue.opacity(0.18), lineWidth: isNext ? 2.5 : 1))
        .shadow(color: isNext ? Theme.blue.opacity(0.25) : .clear, radius: 8, y: 2)
    }
}
