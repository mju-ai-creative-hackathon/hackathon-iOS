import AVFoundation
import UIKit

/// AI 서버 미연결 시 커뮤니티 게시용: 고른 사진(영상은 대표 프레임)을 세로 1080x1920 mp4 로 만든다.
/// 커뮤니티가 영상 전용이라 기기 미리보기도 실제 영상 파일이 있어야 올릴 수 있다.
enum SlideshowExporter {
    static let size = CGSize(width: 1080, height: 1920)

    static func export(_ images: [UIImage], secondsPerImage: Double = 2.0) async throws -> URL {
        guard !images.isEmpty else { throw ShortformPipeline.Failure.failed("영상으로 만들 사진이 없어요.") }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seollog-\(UUID().uuidString)").appendingPathExtension("mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ShortformPipeline.Failure.failed("영상을 만들지 못했어요.") }
        writer.startSession(atSourceTime: .zero)

        // 사진마다 한 프레임 + 마지막에 끝 프레임 (H.264 는 가변 프레임 간격 허용)
        let frames = images + [images[images.count - 1]]
        for (i, image) in frames.enumerated() {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            guard let buffer = pixelBuffer(image, pool: adaptor.pixelBufferPool) else { continue }
            let t = CMTime(seconds: Double(i) * secondsPerImage - (i == images.count ? 0.04 : 0), preferredTimescale: 600)
            adaptor.append(buffer, withPresentationTime: t)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ShortformPipeline.Failure.failed("영상을 만들지 못했어요.") }
        return url
    }

    /// 화면을 꽉 채우도록(aspect fill) 가운데 기준으로 그린다
    private static func pixelBuffer(_ image: UIImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) }
        if out == nil {
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &out)
        }
        guard let buffer = out else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // UIKit 좌표로 그리기 위해 뒤집기
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        UIGraphicsPopContext()
        return buffer
    }
}
