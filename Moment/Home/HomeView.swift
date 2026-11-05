import SwiftUI
import MapKit

/// 홈 (와이어프레임 '홈' 기준)
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(PlacesStore.self) private var places
    @Environment(AuthSession.self) private var auth
    @State private var sheetPlace: PlaceSummary?
    @State private var showAll = false
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9850),
        span: MKCoordinateSpan(latitudeDelta: 0.085, longitudeDelta: 0.085)))
    @State private var selectedPlace: Int64?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    mapCard.padding(.top, 8)
                    intro.padding(.top, 24)
                    shortsBanner.padding(.top, 28)
                    whatToDo.padding(.top, 36)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Theme.bg)
        .task { if places.places.isEmpty { await places.loadInitial() } }
        .sheet(item: $sheetPlace) { p in PlaceDetailSheet(summary: p) }
        .sheet(isPresented: $showAll) { AllPlacesView() }
        .alert("로그인이 필요해요", isPresented: Binding(get: { places.needsLogin }, set: { places.needsLogin = $0 })) {
            Button("로그인") { auth.logout() }
            Button("취소", role: .cancel) {}
        } message: { Text("북마크는 로그인 후 쓸 수 있어요") }
    }

    // MARK: 상단 바
    private var topBar: some View {
        HStack(spacing: 18) {
            BrandLogo(size: 22)
            Spacer()
            Button { store.selectedTab = .tour } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium))
            }
            Button {} label: {
                Image(systemName: "bell").font(.system(size: 20, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(Theme.red).frame(width: 7, height: 7).offset(x: 1, y: -1)
                    }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    // MARK: 지도 (MapKit — 추후 지도 API 연동 지점)
    private var mapCard: some View {
        Map(position: $camera, selection: $selectedPlace) {
            ForEach(places.pins.filter { $0.coordinate != nil }) { place in
                Annotation(place.title, coordinate: place.coordinate!, anchor: .bottom) {
                    MapPin(selected: selectedPlace == place.id)
                }
                .tag(place.id)
                .annotationTitles(selectedPlace == place.id ? .visible : .hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Button { store.selectedTab = .tour } label: {
                HStack(spacing: 4) {
                    Image(systemName: "map").font(.system(size: 12, weight: .semibold))
                    Text("크게 보기").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(.white).shadow(color: .black.opacity(0.12), radius: 4, y: 1))
            }
            .padding(10)
        }
        .padding(.horizontal, 20)
    }

    // MARK: 인트로 + 서울 둘러보기
    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("오늘, 서울 어디로 떠나볼까요?")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
            Text("홍대부터 지금 내게 어울리는 서울의 장소를 발견해 보세요.")
                .font(.system(size: 13)).foregroundStyle(Theme.gray)
            Button { store.selectedTab = .tour } label: {
                HStack(spacing: 6) {
                    Text("서울 둘러보기")
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.red))
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
    }

    // MARK: SEOULY SHORTS 배너
    private var shortsBanner: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.red)
            // 배경 곡선 장식
            Circle().stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 260).offset(x: 190, y: 70)
            Circle().stroke(.white.opacity(0.10), lineWidth: 1).frame(width: 200).offset(x: 230, y: 90)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SEOLLOG SHORTS")
                        .font(.system(size: 10, weight: .heavy)).tracking(1)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("서울에서의 순간을\n영상으로!")
                        .font(.system(size: 21, weight: .heavy)).foregroundStyle(.white)
                        .lineSpacing(2).padding(.top, 8)
                    Text("사진만 골라도 나만의 숏폼이 완성돼요.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).padding(.top, 8)
                    Button { store.selectedTab = .create } label: {
                        HStack(spacing: 4) {
                            Text("숏폼 만들기")
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                    }
                    .padding(.top, 18)
                }
                Spacer(minLength: 0)
                phones
            }
            .padding(.leading, 20).padding(.trailing, 14).padding(.vertical, 22)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
        .onTapGesture { store.selectedTab = .create }
    }

    private var phones: some View {
        ZStack {
            PhoneFrame(url: URL(string: "https://picsum.photos/seed/hanok/300/600")!, play: false)
                .rotationEffect(.degrees(-10)).offset(x: -20, y: -12)
            PhoneFrame(url: URL(string: "https://picsum.photos/seed/palace/300/600")!, play: true)
                .rotationEffect(.degrees(7)).offset(x: 18, y: 12)
        }
        .frame(width: 130, height: 150)
    }

    // MARK: 서울에서 뭐 하지?
    private var whatToDo: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("서울에서 뭐 하지?").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("취향에 맞는 장소를 발견해 보세요.").font(.system(size: 13)).foregroundStyle(Theme.gray)
                }
                Spacer()
                Button { showAll = true } label: {
                    HStack(spacing: 2) {
                        Text("모두 보기")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gray)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(places.categories, id: \.code) { c in
                        chip(c.label, on: places.selected == c.code) { Task { await places.select(c.code) } }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 16)

            HStack(spacing: 4) {
                Image(systemName: "sparkles").foregroundStyle(Theme.orange)
                Text("처음 만나는 서울을 위한 샘플 큐레이션").foregroundStyle(Theme.gray)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 20).padding(.top, 14)

            placeList.padding(.top, 10)
        }
    }

    @ViewBuilder private var placeList: some View {
        if places.isLoading && places.places.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 12).fill(Theme.line.opacity(0.7)).frame(width: 156, height: 118)
                            RoundedRectangle(cornerRadius: 4).fill(Theme.line.opacity(0.7)).frame(width: 110, height: 14)
                            RoundedRectangle(cornerRadius: 4).fill(Theme.line.opacity(0.5)).frame(width: 70, height: 11)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .overlay { ProgressView() }
        } else if let msg = places.errorMessage, places.places.isEmpty {
            VStack(spacing: 10) {
                Text(msg).font(.system(size: 13)).foregroundStyle(Theme.gray).multilineTextAlignment(.center)
                Button { Task { await places.loadInitial() } } label: {
                    Text("다시 시도").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 36)
                        .background(Capsule().fill(Theme.red))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 20)
        } else if places.places.isEmpty {
            Text("아직 등록된 장소가 없어요")
                .font(.system(size: 13)).foregroundStyle(Theme.gray)
                .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(places.places) { place in
                        PlaceCard(place: place) { Task { await places.toggleBookmark(place.id) } }
                            .onTapGesture { open(place) }
                    }
                }
                .padding(.horizontal, 20)
            }
            .opacity(places.isLoading ? 0.5 : 1)
            .animation(.snappy, value: places.selected)
        }
    }

    private func open(_ place: PlaceSummary) {
        selectedPlace = place.id
        sheetPlace = place
        if let c = places.pins.first(where: { $0.id == place.id })?.coordinate {
            withAnimation { camera = .region(MKCoordinateRegion(center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))) }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: on ? .bold : .medium))
                .foregroundStyle(on ? .white : Theme.ink)
                .padding(.horizontal, 16).frame(height: 34)
                .background(Capsule().fill(on ? Theme.red : .white))
                .overlay(Capsule().strokeBorder(on ? .clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 하위 뷰

private struct MapPin: View {
    let selected: Bool
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: selected ? 30 : 22))
            .foregroundStyle(.white, Theme.red)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .animation(.spring(duration: 0.25), value: selected)
    }
}

private struct PhoneFrame: View {
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

struct PlaceCard: View {
    let place: PlaceSummary
    var width: CGFloat = 156
    let onSave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaceImage(urlString: place.imageUrl)
                .frame(width: width, height: width * 0.76)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if place.curated {
                        Text("추천 예시").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)))
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: onSave) {
                        Image(systemName: place.bookmarked ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(8)
                    }
                }
            Text(place.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                .lineLimit(1).padding(.top, 10)
            HStack(spacing: 4) {
                Text(place.district).foregroundStyle(Theme.red).fontWeight(.semibold)
                Text("·").foregroundStyle(Theme.gray)
                Text(place.categoryLabel).foregroundStyle(Theme.gray)
            }
            .font(.system(size: 11)).padding(.top, 4)
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

struct PlaceImage: View {
    let urlString: String?
    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            case .empty: ZStack { Theme.cream; ProgressView() }
            default: ZStack { Theme.cream; Image(systemName: "photo").foregroundStyle(Theme.gray) }
            }
        }
    }
}
