import Foundation
import Observation
import CoreLocation

/// '서울에서 뭐 하지?' 상태: 카테고리 칩, 장소 목록, 지도 핀, 북마크 (Backend /api/places)
@Observable
@MainActor
final class PlacesStore {
    var categories: [PlaceCategoryDTO] = PlacesStore.fallbackCategories
    var selected = "ALL"
    private(set) var places: [PlaceSummary] = []
    private(set) var pins: [PlaceDetail] = []          // 지도용 (좌표는 상세 API 에만 있음)
    private(set) var isLoading = false
    var errorMessage: String?
    /// 비로그인 상태에서 북마크를 누르면 true → 로그인 유도
    var needsLogin = false

    private let api = APIClient.shared
    private weak var auth: AuthSession?

    static let fallbackCategories: [PlaceCategoryDTO] = [
        .init(code: "ALL", label: "전체"), .init(code: "RESTAURANT", label: "맛집"), .init(code: "CAFE", label: "카페"),
        .init(code: "CULTURE", label: "전시·문화"), .init(code: "WALK", label: "산책"), .init(code: "EVENT", label: "이벤트"),
    ]

    func attach(_ auth: AuthSession) { self.auth = auth }
    private var token: String? { auth?.user != nil ? auth?.token : nil }

    /// 홈 진입 시 1회: 칩 + 현재 카테고리 목록 + 지도 핀
    func loadInitial() async {
        async let cats: Void = loadCategories()
        async let list: Void = loadPlaces()
        async let map: Void = loadPins()
        _ = await (cats, list, map)
    }

    func select(_ code: String) async {
        guard code != selected else { return }
        selected = code
        await loadPlaces()
    }

    func loadCategories() async {
        if let c = try? await api.placeCategories(), !c.isEmpty { categories = c }
    }

    func loadPlaces() async {
        let code = selected
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await call { try await self.api.places(category: code, size: 20, token: $0) }
            guard code == selected else { return }   // 칩을 빠르게 바꾼 경우 이전 응답 무시
            places = page.content
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "장소를 불러오지 못했어요."
        }
    }

    /// 지도 핀: 전체 목록 → 상세를 병렬로 불러 좌표 확보
    func loadPins() async {
        guard let all = try? await call({ try await self.api.places(category: "ALL", size: 50, token: $0) }) else { return }
        let t = token   // call 이후라 재발급됐으면 새 토큰
        let details = await withTaskGroup(of: PlaceDetail?.self) { group in
            for p in all.content { group.addTask { try? await APIClient.shared.place(id: p.id, token: t) } }
            var out: [PlaceDetail] = []
            for await d in group { if let d { out.append(d) } }
            return out
        }
        pins = details.filter { $0.latitude != nil && $0.longitude != nil }.sorted { $0.id < $1.id }
    }

    func detail(_ id: Int64) async throws -> PlaceDetail {
        try await call { try await self.api.place(id: id, token: $0) }
    }

    func fetchPage(category: String, page: Int) async throws -> PageResponse<PlaceSummary> {
        try await call { try await self.api.places(category: category, page: page, size: 20, token: $0) }
    }

    func fetchBookmarks() async throws -> PageResponse<PlaceSummary> {
        guard let auth, auth.user != nil else { throw APIError.network("로그인이 필요해요") }
        return try await auth.authorized { try await self.api.bookmarks(page: 0, size: 50, token: $0) }
    }

    /// 목록에 없는 곳(모두 보기/북마크 화면)용 토글. 성공 시 새 상태, 실패/비로그인 시 nil
    func toggleBookmark(id: Int64, current: Bool) async -> Bool? {
        guard let auth, auth.user != nil else { needsLogin = true; return nil }
        do {
            let r = try await auth.authorized { try await self.api.setBookmark(id: id, on: !current, token: $0) }
            apply(id, r.bookmarked)
            return r.bookmarked
        } catch {
            if (error as? APIError)?.status == 401 { needsLogin = true }
            else { errorMessage = (error as? LocalizedError)?.errorDescription ?? "북마크에 실패했어요." }
            return nil
        }
    }

    func isBookmarked(_ id: Int64) -> Bool {
        places.first { $0.id == id }?.bookmarked ?? pins.first { $0.id == id }?.bookmarked ?? false
    }

    /// 낙관적 업데이트 후 실패 시 되돌림
    func toggleBookmark(_ id: Int64) async {
        guard let auth, auth.user != nil else { needsLogin = true; return }
        let target = !isBookmarked(id)
        apply(id, target)
        do {
            let r = try await auth.authorized { try await self.api.setBookmark(id: id, on: target, token: $0) }
            apply(id, r.bookmarked)
        } catch {
            apply(id, !target)
            if (error as? APIError)?.status == 401 { needsLogin = true; return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "북마크에 실패했어요."
        }
    }

    func apply(_ id: Int64, _ on: Bool) {
        if let i = places.firstIndex(where: { $0.id == id }) { places[i].bookmarked = on }
        if let i = pins.firstIndex(where: { $0.id == id }) { pins[i].bookmarked = on }
    }

    /// 로그인/로그아웃 후 bookmarked 값을 다시 채우기
    func reloadForAuthChange() async {
        await loadPlaces()
        await loadPins()
    }

    /// 로그인 상태면 토큰을 붙여 호출 (401 → refresh 후 재시도, 세션 만료면 비로그인으로 호출)
    private func call<R>(_ f: @escaping (String?) async throws -> R) async throws -> R {
        guard let auth else { return try await f(nil) }
        return try await auth.optionalAuth { try await f($0) }
    }
}

extension PlaceDetail {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
