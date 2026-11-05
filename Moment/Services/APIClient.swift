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
struct ShortformCreateBody: Encodable { let title: String }
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
            let s = try dec.singleValueContainer().decode(String.self)
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

    func createShortform(title: String, token: String) async throws -> ShortformProject {
        try await send("POST", "/api/shortforms", token: token, body: ShortformCreateBody(title: title))
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
        do { return try decoder.decode(R.self, from: data) } catch { throw APIError.decoding }
    }
}
