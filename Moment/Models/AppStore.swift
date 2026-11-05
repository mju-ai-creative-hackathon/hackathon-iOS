import SwiftUI
import Observation
import CoreLocation

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
    var courses: [TravelCourse] = MockReels.courses
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
    /// 도장깨기: 스팟에 찍은 사진 저장
    func stamp(courseID: UUID, spotID: UUID, photo: UIImage) {
        guard let c = courses.firstIndex(where: { $0.id == courseID }),
              let s = courses[c].spots.firstIndex(where: { $0.id == spotID }) else { return }
        courses[c].spots[s].capturedPhoto = photo
    }
    func course(_ id: UUID) -> TravelCourse? { courses.first { $0.id == id } }
    var totalStamps: Int { courses.reduce(0) { $0 + $1.stampedCount } }
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

    static func spot(_ name: String, _ desc: String, _ mission: String, _ lat: Double, _ lng: Double, _ seed: String) -> TourSpot {
        TourSpot(name: name, description: desc, mission: mission,
                 coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), previewURL: MockData.photo(seed))
    }

    static let courses: [TravelCourse] = [
        TravelCourse(title: "부산 바다 한 바퀴", region: "부산", summary: "해운대부터 감천까지, 바다 따라 걷는 하루 코스",
                     tags: ["바다", "야경", "뚜벅이"], estimatedTime: "약 6시간", coverURL: MockData.photo("busan"),
                     spots: [
                        spot("해운대 해수욕장", "부산의 상징, 넓은 백사장", "파도가 들어올 때 발끝과 바다를 함께 찍기", 35.1587, 129.1604, "haeundae"),
                        spot("해운대 블루라인파크", "바다 위를 달리는 스카이캡슐", "캡슐 창밖으로 보이는 바다 찍기", 35.1601, 129.1747, "blueline"),
                        spot("광안리 해변", "광안대교 뷰 맛집", "광안대교가 화면 가운데 오게 가로로 찍기", 35.1532, 129.1186, "gwangalli"),
                        spot("흰여울 문화마을", "절벽 위 하얀 골목", "하얀 담장과 바다를 같이 넣어 셀카", 35.0781, 129.0441, "huinnyeoul"),
                        spot("감천 문화마을", "알록달록 언덕 마을", "어린왕자 동상 옆에서 마을 전경 찍기", 35.0975, 129.0106, "gamcheon"),
                     ]),
        TravelCourse(title: "제주 서쪽 노을 코스", region: "제주", summary: "애월에서 협재까지, 노을 맛집만 골랐어요",
                     tags: ["노을", "카페", "드라이브"], estimatedTime: "약 5시간", coverURL: MockData.photo("jejuwest"),
                     spots: [
                        spot("애월 한담 해안산책로", "에메랄드빛 바다 산책길", "산책로 난간 너머 바다 찍기", 33.4628, 126.3104, "aewol"),
                        spot("곽지 해수욕장", "하얀 모래와 투명한 물", "모래 위 발자국 찍기", 33.4505, 126.3048, "gwakji"),
                        spot("협재 해수욕장", "비양도가 보이는 해변", "비양도가 수평선에 걸리게 찍기", 33.3940, 126.2397, "hyeopjae"),
                        spot("수월봉", "노을 명소 절벽", "해 질 녘 하늘 색 담기", 33.2955, 126.1630, "suwolbong"),
                     ]),
        TravelCourse(title: "경주 밤산책", region: "경주", summary: "천년 고도의 야경을 걷는 저녁 코스",
                     tags: ["야경", "역사", "산책"], estimatedTime: "약 3시간", coverURL: MockData.photo("gyeongju"),
                     spots: [
                        spot("첨성대", "신라의 천문대", "조명 켜진 첨성대 전체 찍기", 35.8347, 129.2190, "cheomseongdae"),
                        spot("동궁과 월지", "물에 비친 궁궐 야경", "연못에 비친 반영까지 담기", 35.8349, 129.2266, "wolji"),
                        spot("월정교", "복원된 신라 다리", "다리 정면 대칭 구도로 찍기", 35.8296, 129.2179, "woljeonggyo"),
                     ]),
    ]
}
