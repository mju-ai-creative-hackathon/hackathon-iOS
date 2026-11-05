import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// 갤러리 영상을 tmp 로 복사해 URL 로 받는 Transferable
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum MediaImport {
    /// PhotosPickerItem 하나를 MediaItem 으로 변환. 영상이면 길이(초)도 함께 돌려준다.
    @MainActor
    static func load(_ item: PhotosPickerItem) async -> (MediaItem, Double?)? {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
            let asset = AVURLAsset(url: movie.url)
            let seconds = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 1080, height: 1920)
            var thumb: UIImage?
            if let result = try? await gen.image(at: .zero) { thumb = UIImage(cgImage: result.image) }
            let d = (seconds?.isFinite ?? false) ? seconds : nil
            return (MediaItem(kind: .video(url: movie.url, thumbnail: thumb)), d)
        } else {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else { return nil }
            return (MediaItem(kind: .photo(img)), nil)
        }
    }
}
