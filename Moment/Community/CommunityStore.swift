import Foundation
import Observation

/// 커뮤니티 탐색 상태 (Backend /api/community/posts)
/// 랜덤 탐색은 seed/snapshot/cursor 세션을 유지해야 페이지마다 같은 글이 반복되지 않는다.
@Observable
@MainActor
final class CommunityStore {
    private(set) var posts: [CommunityPost] = []
    private(set) var tags: [CommunityTag] = []
    private(set) var isLoading = false
    private(set) var hasNext = false
    var errorMessage: String?

    var keyword = ""
    private(set) var selectedTag: String?

    private var seed: UUID?
    private var snapshot: String?
    private var cursor: String?
    private var generation = 0          // 검색 조건이 바뀌면 이전 응답 버림

    private let api = APIClient.shared
    private weak var auth: AuthSession?

    func attach(_ auth: AuthSession) { self.auth = auth }

    /// 새 탐색 세션 (처음, 새로고침, 검색어·태그 변경)
    func reload() async {
        generation += 1
        seed = nil; snapshot = nil; cursor = nil
        posts = []; hasNext = false
        async let t: Void = loadTags()
        await loadPage()
        await t
    }

    func loadMoreIfNeeded(current post: CommunityPost) async {
        guard hasNext, !isLoading, post.id == posts.last?.id else { return }
        await loadPage()
    }

    func select(tag: String?) async {
        guard tag != selectedTag else { return }
        selectedTag = tag
        await reload()
    }

    func search() async {
        keyword = keyword.trimmingCharacters(in: .whitespaces)
        await reload()
    }

    func remove(_ id: UUID) {
        posts.removeAll { $0.id == id }
        myPosts.removeAll { $0.id == id }
        mineIds = mineIds.filter { $0 != id }
    }

    // MARK: 내가 만든 V-log — 서버에 /mine 이 없어 올린 게시물 ID 를 단말에 보관 후 상세 조회
    private(set) var myPosts: [CommunityPost] = []
    private let mineKey = "community.mine"
    private var mineIds: [UUID] {
        get { (UserDefaults.standard.stringArray(forKey: mineKey) ?? []).compactMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: mineKey) }
    }

    func rememberMine(_ post: CommunityPost) {
        mineIds = [post.id] + mineIds.filter { $0 != post.id }
        myPosts.removeAll { $0.id == post.id }
        myPosts.insert(post, at: 0)
    }

    func loadMine() async {
        var result: [CommunityPost] = []
        var alive: [UUID] = []
        for id in mineIds {
            if let p = try? await api.communityPost(id: id) { result.append(p); alive.append(id) }
            else if let p = myPosts.first(where: { $0.id == id }) { result.append(p); alive.append(id) }   // 일시 오류면 유지
        }
        mineIds = alive
        myPosts = result
    }

    /// 게시물 저장(북마크) — 서버 API 없음, 앱 실행 중에만 유지
    private(set) var saved: Set<UUID> = []
    func toggleSaved(_ id: UUID) { if saved.contains(id) { saved.remove(id) } else { saved.insert(id) } }

    private func loadTags() async {
        if let t = try? await call({ try await self.api.communityTags(token: $0) }) { tags = t }
    }

    private func loadPage() async {
        let gen = generation
        let kw = keyword.isEmpty ? nil : String(keyword.prefix(100))
        let tag = selectedTag, seed = seed, snapshot = snapshot, cursor = cursor
        isLoading = true
        defer { if gen == generation { isLoading = false } }
        do {
            let feed = try await call {
                try await self.api.explore(keyword: kw, tag: tag, seed: seed, snapshot: snapshot, cursor: cursor, token: $0)
            }
            guard gen == generation else { return }
            let known = Set(posts.map(\.id))
            posts += feed.items.filter { !known.contains($0.id) }
            self.seed = feed.seed; self.snapshot = feed.snapshot; self.cursor = feed.nextCursor
            hasNext = feed.hasNext && feed.nextCursor != nil
            errorMessage = nil
        } catch {
            guard gen == generation else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "게시물을 불러오지 못했어요."
        }
    }

    /// 로그인 상태면 토큰을 붙임(본인 글 제외), 세션 만료면 익명으로
    private func call<R>(_ f: @escaping (String?) async throws -> R) async throws -> R {
        guard let auth else { return try await f(nil) }
        return try await auth.optionalAuth { try await f($0) }
    }
}
