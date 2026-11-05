import SwiftUI

/// 사진 배열을 켄번즈(천천히 확대+이동) 효과로 넘기는 세로 릴스 플레이어. Mock 생성 결과/내 릴스 재생용.
struct SlideshowReelView: View {
    let images: [UIImage]
    var secondsPerImage: Double = 2.5
    var isPlaying: Bool = true
    @State private var index = 0
    @State private var zoom = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if images.indices.contains(index) {
                    Image(uiImage: images[index])
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom ? 1.15 : 1.0, anchor: index.isMultiple(of: 2) ? .topLeading : .bottomTrailing)
                        .clipped()
                        .id(index)
                        .transition(.opacity)
                }
            }
        }
        .task(id: isPlaying) {
            guard isPlaying, !images.isEmpty else { return }
            while !Task.isCancelled {
                zoom = false
                withAnimation(.linear(duration: secondsPerImage)) { zoom = true }
                try? await Task.sleep(for: .seconds(secondsPerImage))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.4)) { index = (index + 1) % images.count }
            }
        }
    }
}
