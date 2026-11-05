import SwiftUI

/// 레퍼런스: 크림 배경 + 코발트 블루 손그림 일러스트 톤 (Soul Thai / Monii 스타일)
enum Theme {
    // MOMENTI 브랜드: 화이트 + 레드. (토큰 이름은 기존 화면 호환 위해 유지: blue = 메인 포인트 컬러)
    static let cream = Color(red: 0.976, green: 0.976, blue: 0.980)     // #F9F9FA 연한 회색 배경
    static let paper = Color.white                                        // 카드/버튼 위 텍스트
    static let blue = Color(red: 0.725, green: 0.204, blue: 0.188)       // #B93430 메인 레드
    static let blueDeep = Color(red: 0.11, green: 0.11, blue: 0.12)      // 제목 텍스트(거의 검정)
    static let blueSoft = Color(red: 0.984, green: 0.925, blue: 0.918)   // #FBECEA 연레드
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let gray = Color(red: 0.45, green: 0.46, blue: 0.48)          // 보조 텍스트
    static let line = Color(red: 0.90, green: 0.90, blue: 0.92)          // 테두리
    static let red = Color(red: 0.725, green: 0.204, blue: 0.188)
    static let orange = Color(red: 0.91, green: 0.71, blue: 0.23)        // 로고 점(머스터드)
    static let bg = Color(red: 0.980, green: 0.976, blue: 0.969)          // #FAF9F7 앱 배경

    static let background = LinearGradient(colors: [bg, bg], startPoint: .top, endPoint: .bottom)

    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func hand(_ size: CGFloat = 18) -> Font { .custom("Noteworthy-Bold", size: size) }   // 손글씨 느낌
    static let body = Font.system(size: 15, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
}

/// 블루 꽉 찬 카드 (레퍼런스의 3분할 파란 박스)
struct BlueCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.blue))
            .foregroundStyle(Theme.paper)
    }
}
/// 크림 카드 + 얇은 블루 테두리 (레퍼런스의 '회원 혜택' 박스)
struct PaperCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.blue.opacity(0.18), lineWidth: 1))
            .foregroundStyle(Theme.blueDeep)
    }
}
extension View {
    func blueCard() -> some View { modifier(BlueCard()) }
    func paperCard() -> some View { modifier(PaperCard()) }
}

/// 세로 점선 구분선 (3분할 카드 사이)
struct DashedVDivider: View {
    var color: Color = Theme.paper.opacity(0.7)
    var body: some View {
        Rectangle().fill(.clear).frame(width: 1)
            .overlay(Line().stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
    struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); return p }
    }
}

/// 블루 캡슐 메인 버튼
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Capsule().fill(Theme.blue))
            .foregroundStyle(Theme.paper)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
