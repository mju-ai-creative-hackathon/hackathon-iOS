import SwiftUI
import Observation

/// 릴스 / 여행 코스 전역 상태. `@Environment(AppStore.self) private var store`
/// 하단 탭: 홈 / 만들기 / 커뮤니티(릴스 공유 피드) / 탐색하기(도장깨기 코스) / 더보기
enum AppTab: Int, CaseIterable { case home, create, reels, tour, more }

@Observable
final class AppStore {
    // 네비게이션: 어디서든 탭 이동 / 릴스 만들기(루트1) 시트 열기
    var selectedTab: AppTab = {
        // 디버그용: 실행 인자 `-tab 2` 로 시작 탭 지정
        let v = UserDefaults.standard.integer(forKey: "tab")
        return AppTab(rawValue: v) ?? .home
    }()
    /// 어디서든 true 로 두면 만들기 탭으로 이동 (RootTabView 가 처리)
    var isCreatingReel = false
    /// 게시 직후 릴스 탭으로 보내기
    func publishAndShow(_ reel: Reel) { publish(reel); selectedTab = .reels }

    var reels: [Reel] = MockReels.reels
    /// 탐색하기 → 만들기로 넘기는 코스 미션 결과물 (CreateView 가 꺼내 씀)
    var createDraft: CreateDraft?
    let generator: ReelGenerationService = MockReelGenerationService()

    /// 생성된 릴스를 릴스 피드 맨 앞에 게시
    func publish(_ reel: Reel) { reels.insert(reel, at: 0) }

    func toggleLike(_ id: Reel.ID) {
        guard let i = reels.firstIndex(where: { $0.id == id }) else { return }
        reels[i].isLiked.toggle(); reels[i].likeCount += reels[i].isLiked ? 1 : -1
    }
    func toggleSave(_ id: Reel.ID) {
        guard let i = reels.firstIndex(where: { $0.id == id }) else { return }
        reels[i].isSaved.toggle()
    }
}

enum MockReels {
    static let videos: [URL] = (1...5).map { Bundle.main.url(forResource: "reel\($0)", withExtension: "mp4")! }

    static let reels: [Reel] = [
        Reel(author: MockData.users[2], content: .remoteVideo(videos[0]), caption: "제주 도장깨기 완주 🍊 AI가 알아서 편집해줌 ㄷㄷ #도장깨기 #제주",
             location: "제주 애월", musicTitle: "Summer Breeze · Moment AI", likeCount: 12840, commentCount: 231, tourCourseTitle: "제주 서쪽 노을 코스"),
        Reel(author: MockData.users[3], content: .remoteVideo(videos[1]), caption: "주말 브이로그 🎞️", location: "서울 성수",
             musicTitle: "Lazy Sunday · Moment AI", likeCount: 3201, commentCount: 54),
        Reel(author: MockData.users[5], content: .remoteVideo(videos[2]), caption: "부산 바다 한 바퀴 🌊 5곳 다 찍음", location: "부산 해운대",
             musicTitle: "Ocean Drive · Moment AI", likeCount: 8890, commentCount: 120, tourCourseTitle: "부산 바다 한 바퀴"),
        Reel(author: MockData.users[0], content: .remoteVideo(videos[3]), caption: "드라이브 🚗", location: nil,
             musicTitle: "Road Trip · Moment AI", likeCount: 940, commentCount: 12),
        Reel(author: MockData.users[6], content: .remoteVideo(videos[4]), caption: "경주 야경 미쳤다", location: "경주 동궁과 월지",
             musicTitle: "Moonlight · Moment AI", likeCount: 5120, commentCount: 88, tourCourseTitle: "경주 밤산책"),
    ]
}

/// 코스 미션으로 찍은 사진·영상 + 연결 정보
struct CreateDraft {
    let title: String
    let media: [MediaItem]
    let courseId: Int64
    let missionIds: [Int64]
}
