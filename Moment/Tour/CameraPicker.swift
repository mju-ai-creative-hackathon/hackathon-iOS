import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// 카메라 촬영 (사진 또는 영상) UIImagePickerController 래퍼
struct CameraPicker: UIViewControllerRepresentable {
    var video = false
    var maxDuration: TimeInterval = 15
    var onPick: (MediaItem) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if video {
            picker.mediaTypes = [UTType.movie.identifier]
            picker.cameraCaptureMode = .video
            picker.videoMaximumDuration = maxDuration
            picker.videoQuality = .typeHigh
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: dest)
                let gen = AVAssetImageGenerator(asset: AVURLAsset(url: dest))
                gen.appliesPreferredTrackTransform = true
                let thumb = (try? gen.copyCGImage(at: .zero, actualTime: nil)).map(UIImage.init(cgImage:))
                parent.onPick(MediaItem(kind: .video(url: dest, thumbnail: thumb)))
            } else if let image = info[.originalImage] as? UIImage {
                parent.onPick(MediaItem(kind: .photo(image)))
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
