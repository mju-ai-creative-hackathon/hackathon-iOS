import Foundation
import Observation
import CoreLocation

/// 탐색하기 상태 (Backend /api/courses)
@Observable
@MainActor
final class TourStore {
    private(set) var regions: [String] = []
    private(set) var courses: [CourseSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// nil = 전체, "저장됨" = 저장한 코스
    private(set) var region: String?
    static let savedFilter = "저장됨"

    // AI 맞춤 코스
    private(set) var recommendations: [CourseDetail] = []
    private(set) var isRecommending = false
    var recommendError: String?

    /// 미션 촬영 결과 (missionId → 사진/영상). 앱 실행 중에만 유지
    var captures: [Int64: MediaItem] = [:]

    let location = LocationProvider()
    private let api = APIClient.shared
    private weak var auth: AuthSession?
    private var generation = 0

    func attach(_ auth: AuthSession) { self.auth = auth }

    func load() async {
        location.request()
        if regions.isEmpty, let r = try? await api.courseRegions() { regions = r }
        await loadCourses()
    }

    func select(region: String?) async {
        guard region != self.region else { return }
        self.region = region
        await loadCourses()
    }

    func loadCourses() async {
        generation += 1
        let gen = generation, region = region
        let (lat, lng) = location.latLng
        isLoading = true
        defer { if gen == generation { isLoading = false } }
        do {
            let page: PageResponse<CourseSummary>
            if region == Self.savedFilter {
                guard let auth else { return }
                page = try await auth.authorized { try await self.api.savedCourses(lat: lat, lng: lng, token: $0) }
            } else {
                page = try await optional { try await self.api.courses(region: region, lat: lat, lng: lng, token: $0) }
            }
            guard gen == generation else { return }
            courses = page.content
            errorMessage = nil
        } catch {
            guard gen == generation else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "코스를 불러오지 못했어요."
        }
    }

    /// 마이 탭 '저장한 코스' (로그인 필요)
    private(set) var savedCourses: [CourseSummary] = []
    func loadSaved() async {
        guard let auth, auth.user != nil else { savedCourses = []; return }
        let (lat, lng) = location.latLng
        if let page = try? await auth.authorized({ try await self.api.savedCourses(lat: lat, lng: lng, token: $0) }) {
            savedCourses = page.content
        }
    }

    func detail(_ id: Int64) async throws -> CourseDetail {
        let (lat, lng) = location.latLng
        return try await optional { try await self.api.course(id: id, lat: lat, lng: lng, token: $0) }
    }

    /// AI 맞춤 코스 (로그인 필요, 30~40초)
    func recommend(_ prompt: String) async {
        guard let auth, !isRecommending else { return }
        let text = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty else { return }
        isRecommending = true; recommendError = nil
        defer { isRecommending = false }
        let (lat, lng) = location.latLng
        do {
            recommendations = try await auth.authorized {
                try await self.api.recommendCourses(prompt: text, lat: lat, lng: lng, token: $0)
            }
            if recommendations.isEmpty { recommendError = "조건에 맞는 코스를 찾지 못했어요. 다르게 말해볼까요?" }
        } catch let e as APIError {
            recommendError = switch e.status {
            case 429: "오늘 AI 추천 횟수를 다 썼어요. 내일 다시 시도해 주세요."
            case 502: "조건에 맞는 장소가 부족해요. 지역이나 테마를 바꿔볼까요?"
            case 503: "AI 추천을 잠시 쓸 수 없어요."
            default: e.errorDescription ?? "추천을 받지 못했어요."
            }
        } catch {
            recommendError = "추천을 받지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    /// 코스 수정 요청 → 새 AI 코스 (로그인 필요)
    private(set) var isRefining = false
    func refine(_ courseId: Int64, prompt: String) async throws -> CourseDetail {
        guard let auth else { throw RefineError(message: "로그인이 필요해요.") }
        let text = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        isRefining = true
        defer { isRefining = false }
        let (lat, lng) = location.latLng
        do {
            return try await auth.authorized {
                try await self.api.refineCourse(id: courseId, prompt: text, lat: lat, lng: lng, token: $0)
            }
        } catch let e as APIError {
            let message: String = switch e.status {
            case 429: "오늘 AI 요청 횟수를 다 썼어요. 내일 다시 시도해 주세요."
            case 502: "조건에 맞는 장소가 부족해요. 다르게 말해볼까요?"
            case 503: "AI 추천을 잠시 쓸 수 없어요."
            default: e.errorDescription ?? "코스를 고치지 못했어요."
            }
            throw RefineError(message: message)
        }
    }
    struct RefineError: LocalizedError { let message: String; var errorDescription: String? { message } }

    func clearRecommendations() { recommendations = []; recommendError = nil }

    /// 저장 토글 → 서버 결과로 목록·추천 상태 갱신
    func setSaved(_ id: Int64, _ on: Bool) async throws -> Bool {
        guard let auth else { return !on }
        let r = try await auth.authorized { try await self.api.setCourseSaved(id: id, on: on, token: $0) }
        if let i = courses.firstIndex(where: { $0.id == id }) { courses[i].saved = r.saved }
        if let i = recommendations.firstIndex(where: { $0.id == id }) { recommendations[i].saved = r.saved }
        if region == Self.savedFilter, !r.saved { courses.removeAll { $0.id == id } }
        if r.saved { Task { await loadSaved() } } else { savedCourses.removeAll { $0.id == id } }
        return r.saved
    }

    private func optional<R>(_ f: @escaping (String?) async throws -> R) async throws -> R {
        guard let auth else { return try await f(nil) }
        return try await auth.optionalAuth { try await f($0) }
    }
}

/// 현재 위치 한 번 받기 (거리·출발 길찾기용). 권한 거부 시 nil
@Observable
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var latLng: (Double?, Double?) { (coordinate?.latitude, coordinate?.longitude) }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { manager.requestLocation() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.coordinate = c }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
