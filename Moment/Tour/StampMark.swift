import SwiftUI

/// 기울어진 'CLEAR' 도장
struct StampMark: View {
    var color: Color = Theme.red
    var size: CGFloat = 84
    var date: Date = Date()

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yy.MM.dd"
        return f.string(from: date)
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 3)
            Circle().strokeBorder(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .padding(6)
            VStack(spacing: 1) {
                Text("CLEAR")
                    .font(.system(size: size * 0.22, weight: .heavy, design: .rounded))
                Text(dateText)
                    .font(.system(size: size * 0.12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Theme.paper.opacity(0.55)))
        .rotationEffect(.degrees(-14))
    }
}
