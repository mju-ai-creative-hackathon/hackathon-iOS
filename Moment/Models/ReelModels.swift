import SwiftUI

/// 릴스에 들어갈 미디어 한 조각 (갤러리/카메라에서 가져온 것)
struct MediaItem: Identifiable {
    let id = UUID()
    enum Kind { case photo(UIImage), video(url: URL, thumbnail: UIImage?) }
    let kind: Kind
    var thumbnail: UIImage? {
        switch kind { case .photo(let i): i; case .video(_, let t): t }
    }
}

/// 영상 스타일 (만들기 STEP 02). code = 백엔드 VideoStyle
enum ReelStyle: String, CaseIterable, Identifiable {
    case cinematic = "시네마틱", dynamic = "다이내믹", vlog = "브이로그", minimal = "미니멀"
    var id: String { rawValue }
    var code: String {
        switch self { case .cinematic: "CINEMATIC"; case .dynamic: "DYNAMIC"; case .vlog: "VLOG"; case .minimal: "MINIMAL" }
    }
    var symbol: String {
        switch self { case .cinematic: "film"; case .dynamic: "bolt"; case .vlog: "camera"; case .minimal: "square" }
    }
    var summary: String {
        switch self {
        case .cinematic: "깊고 차분한 영화 톤"; case .dynamic: "비트에 맞춘 빠른 컷"
        case .vlog: "일상 기록 브이로그"; case .minimal: "담백하고 감성적으로"
        }
    }
    /// 미리보기 카드 문구
    var tagline: String {
        switch self { case .cinematic: "SEOUL, TONIGHT"; case .dynamic: "SEOUL, NOW"; case .vlog: "SEOUL, TODAY"; case .minimal: "SEOUL, QUIET" }
    }
    var headline: String {
        switch self { case .cinematic: "도시의 빛을 따라"; case .dynamic: "멈추지 않는 서울"; case .vlog: "오늘도 서울 산책"; case .minimal: "조용한 서울의 결" }
    }
    var thumbnailSeed: String {
        switch self { case .cinematic: "seoul-night-neon"; case .dynamic: "seoul-crowd-move"; case .vlog: "seoul-cafe-day"; case .minimal: "seoul-concrete" }
    }
}

/// 영상 분위기. code = 백엔드 VideoMood
enum ReelMood: String, CaseIterable, Identifiable {
    case urban = "도시적인", romantic = "로맨틱한", calm = "차분한", energetic = "활기찬"
    var id: String { rawValue }
    var code: String {
        switch self { case .urban: "URBAN"; case .romantic: "ROMANTIC"; case .calm: "CALM"; case .energetic: "ENERGETIC" }
    }
}

/// 배경 음악 (rawValue = 곡 제목)
enum MusicMood: String, CaseIterable, Identifiable {
    case sunset = "Seoul after sunset", bukchon = "Morning in Bukchon", hangang = "Hangang breeze", rain = "Rainy Euljiro", none = "음악 없음"
    var id: String { rawValue }
    var length: String {
        switch self { case .sunset: "00:15"; case .bukchon: "00:20"; case .hangang: "00:30"; case .rain: "00:18"; case .none: "--:--" }
    }
    var mood: String {
        switch self { case .sunset: "잔잔한 시티팝"; case .bukchon: "어쿠스틱"; case .hangang: "경쾌한 로파이"; case .rain: "몽환적인 재즈"; case .none: "원본 소리만" }
    }
}

/// 릴스를 만드는 두 가지 루트
enum ReelSource {
    case gallery                 // 루트1: 사용자가 직접 고른 사진/영상
    case tour(courseId: Int64, missionIds: [Int64])   // 루트2: 탐색하기 코스 촬영 미션
}

/// 백엔드로 보낼 생성 요청
struct ReelGenerationRequest {
    var source: ReelSource
    var media: [MediaItem]
    var style: ReelStyle = .cinematic
    var mood: ReelMood = .urban
    var music: MusicMood = .sunset
    var durationSeconds: Int = 15
    var caption: String = ""
}

/// 생성 진행 단계
struct GenerationProgress {
    var stage: String      // "업로드 중", "장면 분석 중" ...
    var fraction: Double   // 0...1
}

/// 완성된/공유된 릴스
struct Reel: Identifiable {
    let id = UUID()
    let author: User
    enum Content { case remoteVideo(URL), slideshow([UIImage]) }
    let content: Content
    var caption: String
    var location: String?
    var musicTitle: String
    var likeCount: Int
    var commentCount: Int
    var isLiked: Bool = false
    var isSaved: Bool = false
    var isMine: Bool = false
    var tourCourseTitle: String?   // 도장깨기로 만든 릴스면 코스명 배지
}
