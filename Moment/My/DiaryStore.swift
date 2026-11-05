import Foundation
import Observation
import CoreLocation
import CoreMotion

/// 나의 기록(일정 일기장) + 진행 중 일정의 위치·걸음수 수집 (Backend /api/diaries)
///
/// 흐름: 코스 상세 '코스 시작하기' → start(course:) → 단말에서 위치·걸음수 수집 → finish() 로 한 번에 업로드.
/// 수집 데이터는 성공 응답 전까지 단말(UserDefaults)에 보관해 앱이 재실행돼도 이어서 기록한다.
@Observable
@MainActor
final class DiaryStore: NSObject, CLLocationManagerDelegate {
    // 완료된 기록 (마이 탭)
    private(set) var diaries: [DiarySummary] = []
    private(set) var details: [UUID: DiaryDetail] = [:]
    private(set) var isLoading = false
    var errorMessage: String?

    // 진행 중 일정
    private(set) var active: DiaryDetail?
    private(set) var steps = 0                  // 이번 일정 걸음수 (시작 이후)
    private(set) var points: [DiaryPoint] = []  // 수집한 이동 경로
    private(set) var isBusy = false             // 시작/종료 요청 중
    var tripError: String?

    var isTracking: Bool { active != nil }
    var distanceMeters: Double {
        zip(points, points.dropFirst()).reduce(0) { acc, p in
            acc + CLLocation(latitude: p.0.latitude, longitude: p.0.longitude)
                .distance(from: CLLocation(latitude: p.1.latitude, longitude: p.1.longitude))
        }
    }
    /// 대략적인 소모 칼로리 (걸음당 0.04kcal)
    var kcal: Int { Int((Double(steps) * 0.04).rounded()) }

    private let api = APIClient.shared
    private weak var auth: AuthSession?
    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private let saveKey = "diary.tracking"

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        location.distanceFilter = 10
        location.activityType = .fitness
    }

    func attach(_ auth: AuthSession) { self.auth = auth }

    // MARK: 목록 · 상세

    func load() async {
        guard let auth, auth.user != nil else { diaries = []; details = [:]; active = nil; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await auth.authorized { try await self.api.diaries(token: $0) }
            diaries = page.content
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "기록을 불러오지 못했어요."
        }
        await restoreActive()
    }

    @discardableResult
    func detail(_ id: UUID) async -> DiaryDetail? {
        if let d = details[id] { return d }
        guard let auth else { return nil }
        guard let d = try? await auth.authorized({ try await self.api.diary(id: id, token: $0) }) else { return nil }
        details[id] = d
        return d
    }

    func update(_ id: UUID, title: String, memo: String) async throws {
        guard let auth else { return }
        let d = try await auth.authorized { try await self.api.updateDiary(id: id, title: title, memo: memo, token: $0) }
        details[id] = d
        if let i = diaries.firstIndex(where: { $0.id == id }) {
            let s = diaries[i]
            diaries[i] = DiarySummary(id: s.id, courseId: s.courseId, courseTitle: s.courseTitle, title: d.title,
                                      recordDate: s.recordDate, steps: s.steps, status: s.status,
                                      startedAt: s.startedAt, endedAt: s.endedAt, footprintSvg: s.footprintSvg)
        }
    }

    func delete(_ id: UUID) async throws {
        guard let auth else { return }
        try await auth.authorized { try await self.api.deleteDiary(id: id, token: $0) }
        diaries.removeAll { $0.id == id }
        details[id] = nil
    }

    // MARK: 일정 시작 · 종료

    /// 코스로 일정 시작 → 위치·걸음수 수집 시작
    func start(courseId: Int64, title: String?) async {
        guard let auth, !isBusy else { return }
        isBusy = true; tripError = nil
        defer { isBusy = false }
        do {
            let d = try await auth.authorized { try await self.api.startDiary(courseId: courseId, title: title, token: $0) }
            active = d; steps = 0; points = []
            persist()
            beginSensors(from: d.startedAt)
        } catch let e as APIError where e.status == 409 {
            // 이미 진행 중인 일정이 있음 → 그걸 이어서
            await restoreActive()
            tripError = "이미 진행 중인 일정이 있어요. 먼저 종료해 주세요."
        } catch {
            tripError = (error as? LocalizedError)?.errorDescription ?? "일정을 시작하지 못했어요."
        }
    }

    /// 커뮤니티 코스 가져오기로 서버가 바로 시작한 일정을 이어받아 수집 시작
    func adopt(_ d: DiaryDetail) {
        active = d; steps = 0; points = []
        persist()
        beginSensors(from: d.startedAt)
    }

    /// 일정 종료 → 걸음수·경로 업로드. 성공해야 단말 데이터 삭제
    @discardableResult
    func finish() async -> DiaryDetail? {
        guard let auth, let a = active, !isBusy else { return nil }
        isBusy = true; tripError = nil
        defer { isBusy = false }
        stopSensors()
        await refreshSteps(from: a.startedAt)
        // 서버 검증: startedAt ≤ 위치 시각(시간순) ≤ endedAt ≤ 서버 현재+30초.
        // 서버 startedAt 은 마이크로초, 앱은 밀리초로 받으므로 1ms 여유를 두고 범위 안으로 맞춘다.
        let start = a.startedAt.addingTimeInterval(0.002)
        let now = Date()
        var pts = points.filter { $0.recordedAt >= start && $0.recordedAt <= now }
            .sorted { $0.recordedAt < $1.recordedAt }
        if pts.count > 10_000 { pts = Array(pts.suffix(10_000)) }
        let end = max(now, pts.last?.recordedAt ?? now, start)
        do {
            let d = try await auth.authorized {
                try await self.api.completeDiary(id: a.id, body: DiaryCompleteBody(endedAt: end, steps: self.steps, points: pts), token: $0)
            }
            active = nil; points = []; steps = 0
            clearPersisted()
            details[d.id] = d
            await load()
            return d
        } catch let e as APIError where e.status == 409 {
            // 이미 종료됨(이전 요청이 성공했지만 응답을 못 받은 경우)
            active = nil; clearPersisted(); await load()
            return nil
        } catch {
            tripError = (error as? LocalizedError)?.errorDescription ?? "기록을 올리지 못했어요. 다시 시도해 주세요."
            beginSensors(from: a.startedAt)   // 실패하면 계속 수집
            return nil
        }
    }

    /// 진행 중 일정 취소 (기록 삭제)
    func cancel() async {
        guard let auth, let a = active else { return }
        stopSensors()
        try? await auth.authorized { try await self.api.deleteDiary(id: a.id, token: $0) }
        active = nil; points = []; steps = 0
        clearPersisted()
    }

    /// 앱 재실행 시: 서버의 진행 중 일정 + 단말 보관 데이터로 이어서 기록
    private func restoreActive() async {
        guard let auth, auth.user != nil else { return }
        guard let a = try? await auth.authorized({ try await self.api.activeDiary(token: $0) }) else {
            if active != nil { stopSensors() }
            active = nil
            return
        }
        let wasTracking = active?.id == a.id
        active = a
        if !wasTracking {
            if let saved = loadPersisted(), saved.id == a.id { points = saved.points } else { points = [] }
            beginSensors(from: a.startedAt)
        }
    }

    // MARK: 센서

    private func beginSensors(from start: Date) {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        default: break
        }
        location.startUpdatingLocation()
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: start) { [weak self] data, _ in
                guard let n = data?.numberOfSteps.intValue else { return }
                Task { @MainActor in self?.steps = n }
            }
        }
    }

    private func stopSensors() {
        location.stopUpdatingLocation()
        pedometer.stopUpdates()
    }

    private func refreshSteps(from start: Date) async {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let n: Int? = await withCheckedContinuation { c in
            pedometer.queryPedometerData(from: start, to: Date()) { data, _ in c.resume(returning: data?.numberOfSteps.intValue) }
        }
        if let n { steps = n }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let new = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 100 }
            .map { DiaryPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, recordedAt: $0.timestamp) }
        guard !new.isEmpty else { return }
        Task { @MainActor in
            guard let a = self.active else { return }
            let fresh = new.filter { $0.recordedAt >= a.startedAt && $0.recordedAt >= (self.points.last?.recordedAt ?? .distantPast) }
            guard !fresh.isEmpty, self.points.count < 10_000 else { return }
            self.points += fresh
            if self.points.count % 5 == 0 { self.persist() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.active != nil, [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: 단말 보관

    private struct Saved: Codable { let id: UUID; let points: [DiaryPoint] }

    private func persist() {
        guard let a = active, let data = try? JSONEncoder().encode(Saved(id: a.id, points: points)) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }
    private func loadPersisted() -> Saved? {
        UserDefaults.standard.data(forKey: saveKey).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }
    private func clearPersisted() { UserDefaults.standard.removeObject(forKey: saveKey) }
}
