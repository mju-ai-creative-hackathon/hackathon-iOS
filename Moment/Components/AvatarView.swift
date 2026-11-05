import SwiftUI

/// 원형 프로필 이미지. ring: .unseen(그라데이션 링) / .seen(회색 링) / .none
struct AvatarView: View {
    enum Ring { case none, unseen, seen }
    let url: URL
    var size: CGFloat = 32
    var ring: Ring = .none

    static let storyGradient = AngularGradient(
        colors: [Color(red: 0.98, green: 0.80, blue: 0.29), Color(red: 0.98, green: 0.45, blue: 0.17),
                 Color(red: 0.86, green: 0.10, blue: 0.45), Color(red: 0.62, green: 0.13, blue: 0.75),
                 Color(red: 0.98, green: 0.80, blue: 0.29)],
        center: .center, startAngle: .degrees(135), endAngle: .degrees(495))

    var body: some View {
        AsyncImage(url: url) { img in img.resizable().scaledToFill() }
            placeholder: { Color(.systemGray5) }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(ring == .none ? 0 : max(2, size * 0.05))
            .background(Circle().fill(Color(.systemBackground)))
            .padding(ring == .none ? 0 : max(2, size * 0.04))
            .background {
                switch ring {
                case .none: EmptyView()
                case .unseen: Circle().fill(Self.storyGradient)
                case .seen: Circle().fill(Color(.systemGray4))
                }
            }
    }
}
