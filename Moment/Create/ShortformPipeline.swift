import UIKit

/// 숏폼 제작 실제 흐름 (Backend /api/shortforms)
/// 프로젝트 생성 → 소스 업로드 → 제작 등록(Idempotency-Key) → 4초 간격 상태 조회 → 결과 영상 URL
@MainActor
struct ShortformPipeline {
    enum Failure: LocalizedError {
        case renderingUnavailable          // AI 서버 미연결 (options.renderingAvailable=false 또는 503)
        case tooFew(min: Int)
        case fileTooLarge(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .renderingUnavailable: "영상 제작 서버가 아직 연결되지 않았어요."
            case .tooFew(let n): "사진·영상을 \(n)개 이상 골라주세요."
            case .fileTooLarge(let m): m
            case .failed(let m): m
            }
        }
    }

    let auth: AuthSession
    private let api = APIClient.shared

    /// onProgress(0...1, 단계 문구)
    func run(_ request: ReelGenerationRequest, title: String,
             onProgress: @escaping (Double, String) -> Void) async throws -> URL {
        onProgress(0.02, "제작 서버 확인 중")
        let options = try await api.shortformOptions()
        guard options.renderingAvailable else { throw Failure.renderingUnavailable }
        guard request.media.count >= options.minAssets else { throw Failure.tooFew(min: options.minAssets) }

        // 1) 업로드할 파일 준비 (서버 제한: 사진 JPEG/PNG/WebP, 영상 MP4/MOV/WebM)
        let files = try request.media.prefix(options.maxAssets).enumerated().map { i, item in
            try Self.uploadFile(item, index: i, maxImage: options.maxImageBytes, maxVideo: options.maxVideoBytes)
        }

        // 2) 프로젝트 생성
        onProgress(0.05, "프로젝트 만드는 중")
        var courseId: Int64?, missionIds: [Int64] = []
        if case .tour(let c, let m) = request.source { courseId = c; missionIds = m }
        let project = try await auth.authorized {
            try await api.createShortform(title: title, courseId: courseId, missionIds: missionIds, token: $0)
        }

        // 3) 한 파일씩 업로드 (순서 유지, 요청 크기 제한 회피)
        var assetIds: [UUID] = []
        for (i, f) in files.enumerated() {
            try Task.checkCancellation()
            onProgress(0.05 + 0.4 * Double(i) / Double(files.count), "사진 올리는 중 \(i + 1)/\(files.count)")
            let uploaded = try await auth.authorized {
                try await api.uploadShortformAssets(projectId: project.id, files: [f], token: $0)
            }
            assetIds += uploaded.map(\.id)
        }

        // 4) 제작 등록 — 통신 재시도해도 같은 키 유지
        onProgress(0.47, "AI에게 제작 요청 중")
        let key = UUID()
        let body = ShortformRenderBody(style: request.style.code, mood: request.mood.code,
                                       musicId: nil,   // 음악 ID 는 AI 담당과 합의 전
                                       assetIds: assetIds)
        var job: ShortformRender
        do {
            job = try await auth.authorized {
                try await api.requestRender(projectId: project.id, body: body, idempotencyKey: key, token: $0)
            }
        } catch let e as APIError where e.status == 503 {
            throw Failure.renderingUnavailable
        }

        // 5) 상태 조회 (3~5초 간격 권장) — 최대 30분
        let started = Date()
        var creep = 0.5
        while !job.status.isTerminal {
            try await Task.sleep(for: .seconds(4))
            if Date().timeIntervalSince(started) > 1800 { throw Failure.failed("제작 시간이 너무 오래 걸려요. 잠시 후 다시 확인해 주세요.") }
            let current = job
            job = (try? await auth.authorized {
                try await api.render(projectId: current.projectId, renderId: current.id, token: $0)
            }) ?? job
            creep = min(0.95, creep + (0.95 - creep) * 0.08)
            onProgress(creep, job.status.label)
        }

        guard job.status == .SUCCEEDED, let s = job.videoUrl, let url = URL(string: s) else {
            throw Failure.failed(job.errorMessage ?? "영상을 만들지 못했어요. 다시 시도해 주세요.")
        }
        onProgress(1, "완성!")
        return url
    }

    /// MediaItem → 업로드 파일. 사진은 JPEG(긴 변 2160px)로, 영상은 원본 그대로
    static func uploadFile(_ item: MediaItem, index: Int, maxImage: Int, maxVideo: Int) throws -> UploadFile {
        switch item.kind {
        case .photo(let image):
            var quality: CGFloat = 0.85
            var data = resized(image, maxSide: 2160).jpegData(compressionQuality: quality)
            while let d = data, d.count > maxImage, quality > 0.4 {
                quality -= 0.15
                data = resized(image, maxSide: 1600).jpegData(compressionQuality: quality)
            }
            guard let data, data.count <= maxImage else { throw Failure.fileTooLarge("\(index + 1)번째 사진이 너무 커요.") }
            return UploadFile(data: data, filename: String(format: "photo-%02d.jpg", index + 1), mimeType: "image/jpeg")
        case .video(let url, _):
            guard let data = try? Data(contentsOf: url) else { throw Failure.failed("\(index + 1)번째 영상을 읽지 못했어요.") }
            guard data.count <= maxVideo else {
                throw Failure.fileTooLarge("\(index + 1)번째 영상이 \(maxVideo / 1_048_576)MB를 넘어요.")
            }
            let ext = url.pathExtension.lowercased()
            let mime = ext == "mp4" || ext == "m4v" ? "video/mp4" : (ext == "webm" ? "video/webm" : "video/quicktime")
            let outExt = mime == "video/mp4" ? "mp4" : (mime == "video/webm" ? "webm" : "mov")
            return UploadFile(data: data, filename: String(format: "clip-%02d.%@", index + 1, outExt), mimeType: mime)
        }
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

extension ShortformRender.Status {
    var isTerminal: Bool { self == .SUCCEEDED || self == .FAILED }
    var label: String {
        switch self {
        case .QUEUED: "제작 대기 중"
        case .SUBMITTING: "AI 서버로 보내는 중"
        case .PROCESSING: "AI가 편집하는 중"
        case .SUCCEEDED: "완성!"
        case .FAILED: "제작 실패"
        }
    }
}
