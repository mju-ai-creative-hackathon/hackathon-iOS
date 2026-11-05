import Foundation
import Observation
import Security
import UIKit
import GoogleSignIn

/// 로그인 상태 + 토큰 관리.
/// - access 토큰(1시간)·refresh 토큰(7일)은 Keychain 에 저장
/// - API 가 401 을 주면 refresh 로 한 번 재발급 후 재시도 (회전식: 재발급마다 둘 다 교체)
/// - 재발급은 동시에 한 번만 (같은 refresh 토큰을 두 번 쓰면 서버가 세션 전체를 폐기하기 때문)
@Observable
@MainActor
final class AuthSession {
    enum State: Equatable { case checking, signedOut, signedIn(AuthUser), guest }

    private(set) var state: State = .checking
    private let api = APIClient.shared
    private var refreshTask: Task<String, Error>?

    var user: AuthUser? { if case .signedIn(let u) = state { u } else { nil } }
    var token: String? { Keychain.read(.access) }

    // MARK: 앱 시작

    /// 저장된 토큰 확인. 스플래시를 최소 `minSplash` 만큼 보여준다.
    func restore(minSplash: Duration = .seconds(1.2)) async {
        let deadline = ContinuousClock.now + minSplash
        var next: State = .signedOut
        if Keychain.read(.access) != nil || Keychain.read(.refresh) != nil {
            do {
                // /me 가 401 이면 authorized() 가 refresh 후 재시도
                next = .signedIn(try await authorized { try await self.api.me(token: $0) })
            } catch let e as APIError where e.status == 401 {
                clearTokens()
            } catch {
                // 네트워크 오류: 토큰은 남겨두고 로그인 화면으로
            }
        }
        // refresh 토큰까지 만료(7일) → 구글 로그인 상태가 남아 있으면 조용히 재발급
        if next == .signedOut, GIDSignIn.sharedInstance.hasPreviousSignIn(),
           let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn(),
           let r = try? await exchange(user) {
            next = .signedIn(r.user)
        }
        #if DEBUG
        // 디버그 전용: 실행 인자 `-guest YES` 면 로그인 화면 건너뛰기
        if next == .signedOut, UserDefaults.standard.bool(forKey: "guest") { next = .guest }
        #endif
        try? await Task.sleep(until: deadline, clock: .continuous)
        state = next
    }

    // MARK: 로그인

    func login(email: String, password: String) async throws {
        apply(try await api.login(email: email, password: password))
    }

    func signup(email: String, name: String, password: String) async throws {
        apply(try await api.signup(email: email, name: name, password: password))
    }

    /// Google 로그인 → ID 토큰을 백엔드 POST /api/auth/google 로 보내 서비스 토큰 발급
    /// 사용자가 창을 닫으면 false (에러 아님)
    @discardableResult
    func signInWithGoogle() async throws -> Bool {
        guard let presenter = Self.topViewController() else { throw APIError.network("로그인 화면을 띄울 수 없어요.") }
        let result: GIDSignInResult
        do { result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter) }
        catch let e as NSError where e.domain == kGIDSignInErrorDomain && e.code == GIDSignInError.canceled.rawValue {
            return false
        }
        let r = try await exchange(result.user)
        state = .signedIn(r.user)
        return true
    }

    func continueAsGuest() { state = .guest }

    func logout() {
        // 서버 세션 폐기는 실패해도 로컬 로그아웃은 진행
        if let refresh = Keychain.read(.refresh) {
            Task { try? await APIClient.shared.logout(refreshToken: refresh) }
        }
        refreshTask?.cancel(); refreshTask = nil
        clearTokens()
        GIDSignIn.sharedInstance.signOut()
        state = .signedOut
    }

    /// 회원탈퇴: 서버 계정 삭제 후 로컬 토큰·구글 연결까지 정리
    func deleteAccount() async throws {
        try await authorized { try await self.api.deleteAccount(token: $0) }
        refreshTask?.cancel(); refreshTask = nil
        clearTokens()
        try? await GIDSignIn.sharedInstance.disconnect()
        state = .signedOut
    }

    // MARK: 인증 API 호출

    /// 로그인 필수 API. 401 이면 refresh 후 한 번 재시도, 그래도 실패하면 로그아웃하고 에러를 던진다.
    func authorized<R>(_ call: (String) async throws -> R) async throws -> R {
        var stored = Keychain.read(.access)
        if stored == nil { stored = try? await refreshedAccessToken() }
        guard let access = stored else {
            throw APIError.server(status: 401, message: "로그인이 필요해요.", fieldErrors: [:])
        }
        do { return try await call(access) }
        catch let e as APIError where e.status == 401 {
            let fresh: String
            do { fresh = try await refreshedAccessToken() }
            catch {
                // 시작 복원 중이면 상태만 정리, 사용 중이면 로그아웃
                if state == .checking { clearTokens() } else { logout() }
                throw e
            }
            return try await call(fresh)
        }
    }

    /// 로그인 선택 API (목록 등). 로그인 상태면 토큰을 붙이고, 세션이 끝났으면 비로그인으로 호출.
    func optionalAuth<R>(_ call: (String?) async throws -> R) async throws -> R {
        guard user != nil else { return try await call(nil) }
        do { return try await authorized { try await call($0) } }
        catch let e as APIError where e.status == 401 { return try await call(nil) }
    }

    /// refresh 로 새 access 토큰 발급. 진행 중인 재발급이 있으면 그 결과를 같이 기다린다.
    private func refreshedAccessToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let refresh = Keychain.read(.refresh) else {
            throw APIError.server(status: 401, message: "다시 로그인해 주세요.", fieldErrors: [:])
        }
        let task = Task { () throws -> String in
            let r = try await APIClient.shared.refresh(refreshToken: refresh)
            self.save(r)
            return r.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: 내부

    /// 구글 사용자 → (토큰 갱신) → ID 토큰 → 백엔드 토큰 저장
    private func exchange(_ user: GIDGoogleUser) async throws -> AuthResponse {
        let fresh = try await user.refreshTokensIfNeeded()
        guard let idToken = fresh.idToken?.tokenString else { throw APIError.network("구글 ID 토큰을 받지 못했어요.") }
        let r = try await api.googleLogin(idToken: idToken)
        save(r)
        return r
    }

    private func apply(_ r: AuthResponse) {
        save(r)
        state = .signedIn(r.user)
    }

    private func save(_ r: AuthResponse) {
        Keychain.save(r.accessToken, .access)
        // 구버전 서버(refresh 미지원)면 refreshToken 이 없을 수 있음
        if let refresh = r.refreshToken { Keychain.save(refresh, .refresh) } else { Keychain.delete(.refresh) }
    }

    private func clearTokens() {
        Keychain.delete(.access)
        Keychain.delete(.refresh)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var vc = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

/// 토큰 저장용 최소 Keychain 래퍼 (이 기기에서만, 첫 잠금 해제 이후 접근)
enum Keychain {
    enum Item: String { case access = "accessToken", refresh = "refreshToken" }
    private static let service = "com.mju.hackathon.moment"

    private static func base(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: item.rawValue]
    }

    static func save(_ value: String, _ item: Item) {
        delete(item)
        var q = base(item)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ item: Item) -> String? {
        var q = base(item)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ item: Item) { SecItemDelete(base(item) as CFDictionary) }
}
