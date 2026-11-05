import SwiftUI

/// 설로그. 워드마크 (빨강 + 머스터드 점)
struct BrandLogo: View {
    var size: CGFloat = 22
    var showEnglish = false
    var body: some View {
        VStack(spacing: size * 0.35) {
            HStack(spacing: 0) {
                Text("설로그").foregroundStyle(Theme.red)
                Text(".").foregroundStyle(Theme.orange)
            }
            .font(.system(size: size, weight: .heavy))
            .tracking(-0.5)
            if showEnglish {
                HStack(spacing: 0) {
                    Text("Seollog").foregroundStyle(Theme.red)
                    Text(".").foregroundStyle(Theme.orange)
                }
                .font(.system(size: size * 0.42, weight: .bold))
            }
        }
    }
}
