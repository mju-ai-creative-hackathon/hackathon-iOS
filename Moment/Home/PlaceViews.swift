import SwiftUI
import MapKit

/// 장소 상세 시트: store.detail(id) 로 로딩
struct PlaceDetailSheet: View {
    let summary: PlaceSummary
    @Environment(PlacesStore.self) private var places
    @Environment(\.dismiss) private var dismiss
    @State private var detail: PlaceDetail?
    @State private var failed = false

    private var bookmarked: Bool { places.isBookmarked(summary.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlaceImage(urlString: detail?.imageUrl ?? summary.imageUrl)
                    .frame(height: 230).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(summary.title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Button { Task { await places.toggleBookmark(summary.id) } } label: {
                            Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 22)).foregroundStyle(Theme.red)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(summary.district).foregroundStyle(Theme.red).fontWeight(.semibold)
                        Text("·").foregroundStyle(Theme.gray)
                        Text(summary.categoryLabel).foregroundStyle(Theme.gray)
                    }
                    .font(.system(size: 13))

                    if let d = detail {
                        if let desc = d.description, !desc.isEmpty {
                            Text(desc).font(.system(size: 15)).foregroundStyle(Theme.ink).lineSpacing(3).padding(.top, 6)
                        }
                        if let addr = d.address, !addr.isEmpty {
                            Label(addr, systemImage: "mappin.and.ellipse")
                                .font(.system(size: 13)).foregroundStyle(Theme.gray).padding(.top, 4)
                        }
                        if let c = d.coordinate {
                            Map(initialPosition: .region(MKCoordinateRegion(center: c,
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                                Marker(d.title, coordinate: c).tint(Theme.red)
                            }
                            .mapControls { }
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                            .padding(.top, 10)
                        }
                    } else if failed {
                        VStack(spacing: 10) {
                            Text("상세 정보를 불러오지 못했어요").font(.system(size: 13)).foregroundStyle(Theme.gray)
                            Button("다시 시도") { Task { await load() } }
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.red)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 24)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                    }
                }
                .padding(20)
            }
        }
        .background(Theme.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private func load() async {
        failed = false
        do { detail = try await places.detail(summary.id) } catch { failed = true }
    }
}

/// '모두 보기': 칩 + 2열 그리드 + 무한 스크롤
struct AllPlacesView: View {
    @Environment(PlacesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var category = "ALL"
    @State private var items: [PlaceSummary] = []
    @State private var page = 0
    @State private var hasNext = false
    @State private var loading = false
    @State private var error: String?
    @State private var sheetPlace: PlaceSummary?
    @State private var generation = 0

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.categories, id: \.code) { c in
                            Button { category = c.code; Task { await reload() } } label: {
                                let on = category == c.code
                                Text(c.label)
                                    .font(.system(size: 13, weight: on ? .bold : .medium))
                                    .foregroundStyle(on ? .white : Theme.ink)
                                    .padding(.horizontal, 16).frame(height: 34)
                                    .background(Capsule().fill(on ? Theme.red : .white))
                                    .overlay(Capsule().strokeBorder(on ? .clear : Theme.line))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)

                ScrollView {
                    if items.isEmpty && loading {
                        ProgressView().padding(.top, 60)
                    } else if items.isEmpty, let error {
                        VStack(spacing: 10) {
                            Text(error).font(.system(size: 13)).foregroundStyle(Theme.gray)
                            Button("다시 시도") { Task { await reload() } }.foregroundStyle(Theme.red)
                        }.padding(.top, 60)
                    } else if items.isEmpty {
                        Text("아직 등록된 장소가 없어요").font(.system(size: 13)).foregroundStyle(Theme.gray).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: cols, spacing: 18) {
                            ForEach(items) { p in
                                GeometryReader { geo in
                                    PlaceCard(place: p, width: geo.size.width) { Task { await toggle(p) } }
                                        .onTapGesture { sheetPlace = p }
                                }
                                .aspectRatio(0.82, contentMode: .fit)
                                .onAppear { if p.id == items.last?.id { Task { await loadMore() } } }
                            }
                        }
                        .padding(.horizontal, 20)
                        if loading { ProgressView().padding() }
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("서울에서 뭐 하지?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .sheet(item: $sheetPlace) { PlaceDetailSheet(summary: $0) }
            .task { if items.isEmpty { await reload() } }
        }
    }

    private func reload() async {
        generation += 1
        items = []; page = 0; hasNext = false; error = nil
        await fetch(0)
    }

    private func loadMore() async {
        guard hasNext, !loading else { return }
        await fetch(page + 1)
    }

    private func fetch(_ p: Int) async {
        let gen = generation
        loading = true
        defer { if gen == generation { loading = false } }
        do {
            let r = try await store.fetchPage(category: category, page: p)
            guard gen == generation else { return }
            items += r.content
            page = r.page; hasNext = r.hasNext; error = nil
        } catch {
            if gen == generation { self.error = (error as? LocalizedError)?.errorDescription ?? "장소를 불러오지 못했어요." }
        }
    }

    private func toggle(_ p: PlaceSummary) async {
        guard let i = items.firstIndex(where: { $0.id == p.id }) else { return }
        if let now = await store.toggleBookmark(id: p.id, current: items[i].bookmarked),
           let j = items.firstIndex(where: { $0.id == p.id }) { items[j].bookmarked = now }
    }
}

/// 더보기 > 내 북마크
struct BookmarksView: View {
    @Environment(PlacesStore.self) private var store
    @Environment(AuthSession.self) private var auth
    @State private var items: [PlaceSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var sheetPlace: PlaceSummary?

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView()
            } else if let error, items.isEmpty {
                VStack(spacing: 10) {
                    Text(error).font(.system(size: 13)).foregroundStyle(Theme.gray)
                    Button("다시 시도") { Task { await load() } }.foregroundStyle(Theme.red)
                }
            } else if items.isEmpty {
                Text("북마크한 장소가 없어요").font(.system(size: 14)).foregroundStyle(Theme.gray)
            } else {
                List {
                    ForEach(items) { p in
                        HStack(spacing: 12) {
                            PlaceImage(urlString: p.imageUrl).frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                                Text("\(p.district) · \(p.categoryLabel)").font(.system(size: 12)).foregroundStyle(Theme.gray)
                            }
                            Spacer()
                            Button { Task { await remove(p) } } label: {
                                Image(systemName: "bookmark.fill").foregroundStyle(Theme.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { sheetPlace = p }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .navigationTitle("내 북마크")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetPlace, onDismiss: { Task { await load() } }) { PlaceDetailSheet(summary: $0) }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { items = try await store.fetchBookmarks().content; error = nil }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "북마크를 불러오지 못했어요." }
    }

    private func remove(_ p: PlaceSummary) async {
        if let now = await store.toggleBookmark(id: p.id, current: true), !now {
            items.removeAll { $0.id == p.id }
        }
    }
}
