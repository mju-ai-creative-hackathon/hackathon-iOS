import SwiftUI

/// 백엔드 개발자가 실제 AI 생성 API로 교체할 지점.
/// 지금은 Mock 이 단계별 진행률을 흉내내고 업로드한 사진으로 슬라이드쇼 릴스를 돌려준다.
protocol ReelGenerationService {
    func generate(_ request: ReelGenerationRequest,
                  onProgress: @escaping @MainActor (GenerationProgress) -> Void) async throws -> Reel
}

struct MockReelGenerationService: ReelGenerationService {
    func generate(_ request: ReelGenerationRequest,
                  onProgress: @escaping @MainActor (GenerationProgress) -> Void) async throws -> Reel {
        let stages = ["미디어 업로드 중", "장면 분석 중", "베스트 컷 고르는 중", "음악 맞추는 중", "자막·효과 입히는 중", "마무리 중"]
        for (i, s) in stages.enumerated() {
            for k in 0..<10 {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(70))
                await onProgress(GenerationProgress(stage: s, fraction: (Double(i) + Double(k) / 10) / Double(stages.count)))
            }
        }
        await onProgress(GenerationProgress(stage: "완성!", fraction: 1))
        let images = request.media.compactMap(\.thumbnail)
        return Reel(author: MockData.me, content: .slideshow(images),
                    caption: request.caption, location: nil,
                    musicTitle: request.music == .none ? "원본 오디오" : "\(request.music.rawValue) · 설로그",
                    likeCount: 0, commentCount: 0, isMine: true)
    }
}
