import Foundation

// MARK: - 백엔드 DTO (Backend: com.example.backend.auth.dto 와 1:1)

struct AuthUser: Codable, Equatable {
    let id: UUID
    let email: String
    let name: String
    let profileImageUrl: String?
    let createdAt: Date?
}

struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    /// refresh 미지원 서버 대비 옵셔널
    let refreshToken: String?
    let refreshExpiresIn: Int?
    let user: AuthUser
}

struct RefreshBody: Encodable { let refreshToken: String }
struct EmptyResponse: Decodable {}

// MARK: - 장소 DTO (Backend: com.example.backend.place.dto)

struct PlaceCategoryDTO: Codable, Hashable { let code: String; let label: String }

struct PlaceSummary: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let district: String
    let category: String
    let categoryLabel: String
    let imageUrl: String?
    let curated: Bool
    var bookmarked: Bool
}

struct PlaceDetail: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let district: String
    let category: String
    let categoryLabel: String
    let imageUrl: String?
    let curated: Bool
    var bookmarked: Bool
    let description: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

struct PageResponse<T: Codable>: Codable {
    let content: [T]
    let page: Int
    let size: Int
    let totalElements: Int
    let hasNext: Bool
}

struct BookmarkResult: Codable { let placeId: Int64; let bookmarked: Bool }

// MARK: - 숏폼 DTO (Backend: com.example.backend.shortform.ShortformDtos)

struct ShortformOption: Codable, Hashable { let code: String; let label: String }
struct ShortformOptions: Codable {
    let styles: [ShortformOption]
    let moods: [ShortformOption]
    let minAssets: Int
    let maxAssets: Int
    let maxImageBytes: Int
    let maxVideoBytes: Int
    /// false 면 AI 서버 미연결 → 제작 요청 시 503
    let renderingAvailable: Bool
}
struct ShortformAsset: Codable, Identifiable {
    let id: UUID
    let originalFilename: String?
    let contentType: String
    let sizeBytes: Int
    let kind: String            // PHOTO | VIDEO
    let missionId: UUID?
    let contentUrl: String       // 인증 필요한 상대 경로
}
struct ShortformRender: Codable, Identifiable {
    enum Status: String, Codable { case QUEUED, SUBMITTING, PROCESSING, SUCCEEDED, FAILED }
    let id: UUID
    let projectId: UUID
    let status: Status
    let style: String
    let mood: String
    let musicId: String?
    let videoUrl: String?
    let thumbnailUrl: String?
    let errorCode: String?
    let errorMessage: String?
}
struct ShortformProject: Codable, Identifiable {
    let id: UUID
    let title: String
    let assets: [ShortformAsset]
    let latestRender: ShortformRender?
}
struct ShortformCreateBody: Encodable {
    let title: String
    var courseId: Int64? = nil          // 코스 촬영 미션으로 만들 때 (선택)
    var missionIds: [Int64]? = nil
}
struct ShortformRenderBody: Encodable {
    let style: String
    let mood: String
    let musicId: String?
    let assetIds: [UUID]
}

/// multipart 로 올릴 파일 하나
struct UploadFile {
    let data: Data
    let filename: String
    let mimeType: String
}

// MARK: - 커뮤니티 DTO (Backend: com.example.backend.community.CommunityDtos)

struct CommunityAuthor: Codable, Hashable { let id: UUID; let name: String; let profileImageUrl: String? }
struct CommunityMedia: Codable, Hashable, Identifiable {
    let id: UUID
    let kind: String            // PHOTO | VIDEO
    let contentType: String
    let sizeBytes: Int
    let url: String             // 백엔드 상대 경로 (공개)
    var isVideo: Bool { kind == "VIDEO" }
}
struct CommunityPost: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let caption: String?
    let author: CommunityAuthor
    let tags: [String]
    let thumbnailUrl: String?
    let media: [CommunityMedia]
    let createdAt: Date?
}
struct CommunityFeed: Codable {
    let items: [CommunityPost]
    let seed: UUID?
    let snapshot: String?       // 그대로 다음 요청에 되돌려 보냄
    let nextCursor: String?
    let hasNext: Bool
}
struct CommunityTag: Codable, Hashable { let tag: String; let postCount: Int }
struct CommunityCreateBody: Encodable { let title: String; let caption: String?; let tags: [String] }

// MARK: 코스 DTO (Backend /api/courses)

struct CourseSummary: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let summary: String?
    let region: String?
    let source: String          // PRESET | AI
    let totalMinutes: Int
    let estimatedCost: Int?
    let stopCount: Int
    let stopNames: [String]
    let thumbnailUrl: String?
    let distanceMeters: Int?
    var saved: Bool
}

struct CourseStop: Codable, Hashable, Identifiable {
    let seq: Int
    let name: String
    let description: String?
    let address: String?
    let lat: Double
    let lng: Double
    let imageUrl: String?
    let startTime: String?          // 그날의 "HH:mm"
    let stayMinutes: Int
    let day: Int?                   // 여행 일차(1부터). 없으면 1일차
    var id: Int { seq }
    var dayNo: Int { max(1, day ?? 1) }
}

struct CourseLeg: Codable, Hashable {
    let fromSeq: Int
    let toSeq: Int
    let fromName: String?
    let toName: String?
    let distanceMeters: Int
    let estMinutes: Int
    let mode: String            // WALK | PUBLIC
    let naverMapUrl: String?
    let googleMapsUrl: String?
}

struct CourseMission: Codable, Hashable, Identifiable {
    let id: Int64
    let stopSeq: Int
    let kind: String            // PHOTO | VIDEO
    let title: String
    let guide: String?
    let durationSec: Int?
    var isVideo: Bool { kind == "VIDEO" }
}

struct CourseDetail: Codable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let summary: String?
    let region: String?
    let source: String
    let totalMinutes: Int
    let estimatedCost: Int?
    let stopCount: Int
    let thumbnailUrl: String?
    let distanceMeters: Int?
    let prompt: String?
    let stops: [CourseStop]
    let legs: [CourseLeg]
    let startLeg: CourseLeg?
    let origin: CourseOrigin?       // 프롬프트에서 뽑은 출발지 (stops 에는 없음)
    let missions: [CourseMission]
    var saved: Bool
}

struct CourseOrigin: Codable, Hashable { let name: String; let address: String?; let lat: Double; let lng: Double }

// MARK: 나의 기록 · 일정 일기장 DTO (Backend /api/diaries)

struct DiaryPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let recordedAt: Date
}

struct DiarySummary: Codable, Identifiable, Hashable {
    let id: UUID
    let courseId: Int64?
    let courseTitle: String?
    let title: String
    let recordDate: String          // "YYYY-MM-DD" (Asia/Seoul)
    let steps: Int
    let status: String              // ACTIVE | COMPLETED
    let startedAt: Date
    let endedAt: Date?
    let footprintSvg: String?
}

struct DiaryDetail: Codable, Identifiable, Hashable {
    let id: UUID
    let courseId: Int64?
    let courseTitle: String?
    let title: String
    let memo: String?
    let recordDate: String
    let steps: Int
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let points: [DiaryPoint]
    let footprintSvg: String?
}

/// 204(No Content) 를 nil 로 받기 위한 래퍼
protocol EmptyDecodable { static var emptyValue: Self { get } }
struct MaybeDiary: Decodable, EmptyDecodable {
    let value: DiaryDetail?
    static var emptyValue: MaybeDiary { MaybeDiary(value: nil) }
    init(value: DiaryDetail?) { self.value = value }
    init(from decoder: Decoder) throws { value = try DiaryDetail(from: decoder) }
}

struct DiaryStartBody: Encodable { let courseId: Int64; let title: String? }
struct DiaryCompleteBody: Encodable { let endedAt: Date; let steps: Int; let points: [DiaryPoint] }
struct DiaryUpdateBody: Encodable { let title: String; let memo: String }

struct CourseSaveResult: Codable { let courseId: Int64; let saved: Bool }
struct CourseRecommendBody: Encodable { let prompt: String; let lat: Double?; let lng: Double? }
struct CourseRecommendResponse: Codable { let courses: [CourseDetail] }

struct SignupBody: Encodable { let email: String; let name: String; let password: String }
struct GoogleLoginBody: Encodable { let idToken: String }
struct LoginBody: Encodable { let email: String; let password: String }

/// 백엔드 ApiError { code, message, errors{field: msg}, timestamp }
struct APIErrorBody: Decodable {
    let code: String?
    let message: String?
    let errors: [String: String]?
}

enum APIError: LocalizedError {
    case server(status: Int, message: String, fieldErrors: [String: String])
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .server(_, let message, let fields):
            // 필드 검증 에러가 있으면 첫 번째 메시지를 보여줌
            return fields.values.first ?? message
        case .network(let m): return m
        case .decoding: return "서버 응답을 해석하지 못했어요."
        }
    }
    var status: Int? { if case .server(let s, _, _) = self { return s }; return nil }
    var fieldErrors: [String: String] {
        if case .server(_, _, let f) = self { return f }
        return [:]
    }
}

// MARK: - API 클라이언트

struct APIClient {
    static let shared = APIClient()

    /// 우선순위: 실행 인자 `-apiBaseURL http://...` > Info.plist API_BASE_URL > localhost
    let baseURL: URL = {
        if let s = UserDefaults.standard.string(forKey: "apiBaseURL"), let u = URL(string: s) { return u }
        if let s = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String, let u = URL(string: s) { return u }
        return URL(string: "https://3-39-47-78.sslip.io")!
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            var s = try dec.singleValueContainer().decode(String.self)
            // 서버 Instant 는 소수점 6~9자리 → ISO8601DateFormatter 가 읽을 수 있게 3자리로 자름
            if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
                s.replaceSubrange(r, with: String(s[r].prefix(4)))
            }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s) ?? Date()
        }
        return d
    }()

    func signup(email: String, name: String, password: String) async throws -> AuthResponse {
        try await send("POST", "/api/auth/signup", body: SignupBody(email: email, name: name, password: password))
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await send("POST", "/api/auth/login", body: LoginBody(email: email, password: password))
    }

    /// Google ID 토큰(accessToken/serverAuthCode 아님)을 보내 서비스 JWT 를 받는다
    func googleLogin(idToken: String) async throws -> AuthResponse {
        try await send("POST", "/api/auth/google", body: GoogleLoginBody(idToken: idToken))
    }

    /// 토큰 재발급(회전). access·refresh 둘 다 새로 받는다
    func refresh(refreshToken: String) async throws -> AuthResponse {
        try await send("POST", "/api/auth/refresh", body: RefreshBody(refreshToken: refreshToken))
    }

    /// 서버 refresh 세션 폐기 (204)
    func logout(refreshToken: String) async throws {
        let _: EmptyResponse = try await send("POST", "/api/auth/logout", body: RefreshBody(refreshToken: refreshToken))
    }

    /// 회원탈퇴 (204). 계정·refresh 세션·북마크 삭제
    func deleteAccount(token: String) async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/auth/me", token: token, body: Optional<LoginBody>.none)
    }

    func me(token: String) async throws -> AuthUser {
        try await send("GET", "/api/auth/me", token: token, body: Optional<LoginBody>.none)
    }

    // MARK: 장소 (Backend /api/places)

    func placeCategories() async throws -> [PlaceCategoryDTO] {
        try await send("GET", "/api/places/categories", body: Optional<LoginBody>.none)
    }

    /// category: "ALL" | "RESTAURANT" | ... , curated: true 면 '추천 예시'만
    func places(category: String = "ALL", curated: Bool? = nil, page: Int = 0, size: Int = 10,
                token: String?) async throws -> PageResponse<PlaceSummary> {
        var q = [URLQueryItem(name: "category", value: category),
                 URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "size", value: "\(size)")]
        if let curated { q.append(URLQueryItem(name: "curated", value: curated ? "true" : "false")) }
        return try await send("GET", "/api/places", query: q, token: token, body: Optional<LoginBody>.none)
    }

    func place(id: Int64, token: String?) async throws -> PlaceDetail {
        try await send("GET", "/api/places/\(id)", token: token, body: Optional<LoginBody>.none)
    }

    /// 북마크 켜기(PUT)/끄기(DELETE). 멱등. 로그인 필요
    func setBookmark(id: Int64, on: Bool, token: String) async throws -> BookmarkResult {
        try await send(on ? "PUT" : "DELETE", "/api/places/\(id)/bookmark", token: token, body: Optional<LoginBody>.none)
    }

    func bookmarks(page: Int = 0, size: Int = 20, token: String) async throws -> PageResponse<PlaceSummary> {
        try await send("GET", "/api/places/bookmarks",
                       query: [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "size", value: "\(size)")],
                       token: token, body: Optional<LoginBody>.none)
    }

    // MARK: 숏폼 (Backend /api/shortforms) — options 외에는 로그인 필요

    func shortformOptions() async throws -> ShortformOptions {
        try await send("GET", "/api/shortforms/options", body: Optional<LoginBody>.none)
    }

    func createShortform(title: String, courseId: Int64? = nil, missionIds: [Int64] = [],
                         token: String) async throws -> ShortformProject {
        let body = ShortformCreateBody(title: title, courseId: courseId,
                                       missionIds: courseId == nil || missionIds.isEmpty ? nil : Array(missionIds.prefix(20)))
        return try await send("POST", "/api/shortforms", token: token, body: body)
    }

    func shortform(id: UUID, token: String) async throws -> ShortformProject {
        try await send("GET", "/api/shortforms/\(id.uuidString.lowercased())", token: token, body: Optional<LoginBody>.none)
    }

    /// multipart `files` 반복 필드로 업로드 (201, 등록된 소스 배열)
    func uploadShortformAssets(projectId: UUID, files: [UploadFile], missionId: UUID? = nil,
                               token: String) async throws -> [ShortformAsset] {
        let boundary = "SeollogBoundary-\(UUID().uuidString)"
        var body = Data()
        func line(_ s: String) { body.append(Data(s.utf8)) }
        if let missionId {
            line("--\(boundary)\r\nContent-Disposition: form-data; name=\"missionId\"\r\n\r\n\(missionId.uuidString.lowercased())\r\n")
        }
        for f in files {
            let safeName = f.filename.replacingOccurrences(of: "\"", with: "")
            line("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(safeName)\"\r\n")
            line("Content-Type: \(f.mimeType)\r\n\r\n")
            body.append(f.data)
            line("\r\n")
        }
        line("--\(boundary)--\r\n")
        return try await send("POST", "/api/shortforms/\(projectId.uuidString.lowercased())/assets", token: token,
                              rawBody: body, contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120)
    }

    /// 제작 등록 (202). 재시도 시 같은 idempotencyKey 를 써야 중복 제작이 안 됨
    func requestRender(projectId: UUID, body: ShortformRenderBody, idempotencyKey: UUID,
                       token: String) async throws -> ShortformRender {
        try await send("POST", "/api/shortforms/\(projectId.uuidString.lowercased())/renders", token: token,
                       headers: ["Idempotency-Key": idempotencyKey.uuidString.lowercased()], body: body)
    }

    func render(projectId: UUID, renderId: UUID, token: String) async throws -> ShortformRender {
        try await send("GET", "/api/shortforms/\(projectId.uuidString.lowercased())/renders/\(renderId.uuidString.lowercased())",
                       token: token, body: Optional<LoginBody>.none)
    }

    // MARK: 커뮤니티 (Backend /api/community/posts)

    /// 랜덤 탐색. 다음 페이지는 응답의 seed/snapshot/nextCursor 를 그대로 전달
    func explore(keyword: String?, tag: String?, size: Int = 21, seed: UUID?, snapshot: String?, cursor: String?,
                 token: String?) async throws -> CommunityFeed {
        var q = [URLQueryItem(name: "size", value: "\(size)")]
        if let keyword, !keyword.isEmpty { q.append(.init(name: "keyword", value: keyword)) }
        if let tag { q.append(.init(name: "tag", value: tag)) }
        if let seed { q.append(.init(name: "seed", value: seed.uuidString.lowercased())) }
        if let snapshot { q.append(.init(name: "snapshot", value: snapshot)) }
        if let cursor { q.append(.init(name: "cursor", value: cursor)) }
        return try await send("GET", "/api/community/posts/explore", query: q, token: token, body: Optional<LoginBody>.none)
    }

    func communityTags(limit: Int = 15, token: String?) async throws -> [CommunityTag] {
        try await send("GET", "/api/community/posts/tags", query: [.init(name: "limit", value: "\(limit)")],
                       token: token, body: Optional<LoginBody>.none)
    }

    func communityPost(id: UUID) async throws -> CommunityPost {
        try await send("GET", "/api/community/posts/\(id.uuidString.lowercased())", body: Optional<LoginBody>.none)
    }

    func deleteCommunityPost(id: UUID, token: String) async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/community/posts/\(id.uuidString.lowercased())",
                                              token: token, body: Optional<LoginBody>.none)
    }

    /// 게시물 등록: `post`(JSON) + `files`(1~10) + 첫 파일이 영상이면 `cover`(사진) 필수
    /// 커뮤니티는 숏폼 영상 전용: `post` JSON + `video` 1개 + `cover` 사진(필수)
    func createCommunityPost(_ post: CommunityCreateBody, video: UploadFile, cover: UploadFile,
                             token: String) async throws -> CommunityPost {
        let parts: [(name: String, file: UploadFile)] = [
            ("post", UploadFile(data: try JSONEncoder().encode(post), filename: "post.json", mimeType: "application/json")),
            ("video", video), ("cover", cover),
        ]
        let (body, type) = Self.multipart(parts)
        return try await send("POST", "/api/community/posts", token: token, rawBody: body, contentType: type, timeout: 180)
    }

    // MARK: 코스 (탐색하기) — 목록·상세는 비로그인 가능, 저장·AI 추천은 로그인

    func courseRegions() async throws -> [String] {
        try await send("GET", "/api/courses/regions", body: Optional<LoginBody>.none)
    }

    func courses(region: String?, lat: Double?, lng: Double?, page: Int = 0, size: Int = 20,
                 token: String?) async throws -> PageResponse<CourseSummary> {
        var q = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "size", value: "\(size)")]
        if let region { q.append(URLQueryItem(name: "region", value: region)) }
        q += Self.location(lat, lng)
        return try await send("GET", "/api/courses", query: q, token: token, body: Optional<LoginBody>.none)
    }

    func savedCourses(lat: Double?, lng: Double?, page: Int = 0, size: Int = 20,
                      token: String) async throws -> PageResponse<CourseSummary> {
        let q = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "size", value: "\(size)")] + Self.location(lat, lng)
        return try await send("GET", "/api/courses/saved", query: q, token: token, body: Optional<LoginBody>.none)
    }

    func course(id: Int64, lat: Double?, lng: Double?, token: String?) async throws -> CourseDetail {
        try await send("GET", "/api/courses/\(id)", query: Self.location(lat, lng), token: token, body: Optional<LoginBody>.none)
    }

    func setCourseSaved(id: Int64, on: Bool, token: String) async throws -> CourseSaveResult {
        try await send(on ? "PUT" : "DELETE", "/api/courses/\(id)/save", token: token, body: Optional<LoginBody>.none)
    }

    /// AI 맞춤 코스 최대 3개. 10~30초 걸림, 하루 20회
    func recommendCourses(prompt: String, lat: Double?, lng: Double?, token: String) async throws -> [CourseDetail] {
        let body = try JSONEncoder().encode(CourseRecommendBody(prompt: prompt, lat: lat, lng: lng))
        let r: CourseRecommendResponse = try await send("POST", "/api/courses/recommendations", token: token,
                                                        rawBody: body, contentType: "application/json", timeout: 90)
        return r.courses
    }

    /// 기존 코스(기본/내 AI)를 프롬프트대로 고친 새 AI 코스 1개. 원본은 그대로
    func refineCourse(id: Int64, prompt: String, lat: Double?, lng: Double?, token: String) async throws -> CourseDetail {
        let body = try JSONEncoder().encode(CourseRecommendBody(prompt: prompt, lat: lat, lng: lng))
        return try await send("POST", "/api/courses/\(id)/refinements", token: token,
                              rawBody: body, contentType: "application/json", timeout: 90)
    }

    // MARK: 나의 기록 · 일정 일기장 (모두 로그인 필요)

    /// 시각은 밀리초까지 보냄 (.iso8601 은 초 단위로 잘라서 일정 시작 직후 위치가 시작보다 이른 값이 됨)
    private static let isoEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var c = enc.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        return e
    }()

    /// 일정 시작 (진행 중인 일정이 있으면 409)
    func startDiary(courseId: Int64, title: String?, token: String) async throws -> DiaryDetail {
        try await send("POST", "/api/diaries", token: token,
                       rawBody: try Self.isoEncoder.encode(DiaryStartBody(courseId: courseId, title: title)),
                       contentType: "application/json")
    }

    /// 진행 중 일정 (없으면 nil)
    func activeDiary(token: String) async throws -> DiaryDetail? {
        let r: MaybeDiary = try await send("GET", "/api/diaries/active", token: token, rawBody: nil, contentType: nil)
        return r.value
    }

    /// 일정 종료: 이동 경로 + 이번 일정 걸음수 업로드
    func completeDiary(id: UUID, body: DiaryCompleteBody, token: String) async throws -> DiaryDetail {
        try await send("POST", "/api/diaries/\(id.uuidString.lowercased())/complete", token: token,
                       rawBody: try Self.isoEncoder.encode(body), contentType: "application/json", timeout: 60)
    }

    func diaries(page: Int = 0, size: Int = 20, token: String) async throws -> PageResponse<DiarySummary> {
        try await send("GET", "/api/diaries",
                       query: [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "size", value: "\(size)")],
                       token: token, body: Optional<LoginBody>.none)
    }

    func diary(id: UUID, token: String) async throws -> DiaryDetail {
        try await send("GET", "/api/diaries/\(id.uuidString.lowercased())", token: token, body: Optional<LoginBody>.none)
    }

    func updateDiary(id: UUID, title: String, memo: String, token: String) async throws -> DiaryDetail {
        try await send("PATCH", "/api/diaries/\(id.uuidString.lowercased())", token: token,
                       body: DiaryUpdateBody(title: title, memo: memo))
    }

    /// 삭제 · 진행 중 일정 취소
    func deleteDiary(id: UUID, token: String) async throws {
        let _: EmptyResponse = try await send("DELETE", "/api/diaries/\(id.uuidString.lowercased())", token: token,
                                              body: Optional<LoginBody>.none)
    }

    private static func location(_ lat: Double?, _ lng: Double?) -> [URLQueryItem] {
        guard let lat, let lng else { return [] }
        return [URLQueryItem(name: "lat", value: String(format: "%.6f", lat)),
                URLQueryItem(name: "lng", value: String(format: "%.6f", lng))]
    }

    /// 백엔드 상대 경로(/api/...) → 절대 URL
    func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    static func multipart(_ parts: [(name: String, file: UploadFile)]) -> (Data, String) {
        let boundary = "SeollogBoundary-\(UUID().uuidString)"
        var body = Data()
        for p in parts {
            let name = p.file.filename.replacingOccurrences(of: "\"", with: "")
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(p.name)\"; filename=\"\(name)\"\r\nContent-Type: \(p.file.mimeType)\r\n\r\n".utf8))
            body.append(p.file.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return (body, "multipart/form-data; boundary=\(boundary)")
    }

    private func send<B: Encodable, R: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                                  token: String? = nil, headers: [String: String] = [:],
                                                  body: B?) async throws -> R {
        let raw = try body.map { try JSONEncoder().encode($0) }
        return try await send(method, path, query: query, token: token, headers: headers,
                              rawBody: raw, contentType: raw == nil ? nil : "application/json")
    }

    private func send<R: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                    token: String? = nil, headers: [String: String] = [:],
                                    rawBody: Data?, contentType: String?, timeout: TimeInterval = 15) async throws -> R {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let rawBody {
            if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            req.httpBody = rawBody
        }

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw APIError.network("서버에 연결할 수 없어요. (\(baseURL.host() ?? "")) 백엔드가 켜져 있는지 확인해 주세요.") }

        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let e = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.server(status: status, message: e?.message ?? "요청에 실패했어요. (\(status))",
                                  fieldErrors: e?.errors ?? [:])
        }
        if data.isEmpty, let empty = EmptyResponse() as? R { return empty }
        if data.isEmpty, let t = R.self as? EmptyDecodable.Type, let v = t.emptyValue as? R { return v }   // 204
        do { return try decoder.decode(R.self, from: data) } catch { throw APIError.decoding }
    }
}
