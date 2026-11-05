import SwiftUI
import UIKit

/// AsyncImage 대체: 메모리 캐시 + 실패 시 재시도.
/// AsyncImage 는 Lazy 그리드에서 스크롤로 셀이 빠르게 재사용되면 요청이 취소된 채 빈칸으로 남고,
/// 서버가 `Cache-Control: no-store` 라 매번 새로 받는다 → 썸네일이 종종 누락됨.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    init() { cache.countLimit = 300 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        if let t = inflight[url] { return await t.value }
        // 셀이 사라져도 내려받기는 끝까지 (다음에 다시 보일 때 캐시로)
        let t = Task.detached(priority: .userInitiated) { () -> UIImage? in
            for attempt in 0..<3 {
                if let (data, resp) = try? await URLSession.shared.data(from: url),
                   (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                   let img = UIImage(data: data) {
                    return img.preparingForDisplay() ?? img
                }
                try? await Task.sleep(for: .milliseconds(300 * (attempt + 1)))
            }
            return nil
        }
        inflight[url] = t
        let img = await t.value
        inflight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}

struct CachedImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?) {
        self.url = url
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0) })
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(Theme.line)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { failed = true; return }
            if image == nil { image = ImageCache.shared.cached(url) }
            guard image == nil else { return }
            if let img = await ImageCache.shared.load(url) {
                withAnimation(.easeOut(duration: 0.15)) { image = img }
            } else { failed = true }
        }
    }
}
