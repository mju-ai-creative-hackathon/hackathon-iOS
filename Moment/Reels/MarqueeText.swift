import SwiftUI

/// 길면 흐르는(마퀴) 한 줄 텍스트. 짧으면 정지.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 13, weight: .medium)
    var gap: CGFloat = 32

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }

    var body: some View {
        Color.clear
            .frame(height: 18)
            .frame(maxWidth: .infinity)
            .background(GeometryReader { g in
                Color.clear.onAppear { containerWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in containerWidth = w }
            })
            .overlay(alignment: .leading) {
                HStack(spacing: gap) {
                    label
                    if needsScroll { label }
                }
                .offset(x: offset)
                .fixedSize()
            }
            .clipped()
            .task(id: "\(text)-\(needsScroll)-\(Int(textWidth))") { await run() }
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
            .background(GeometryReader { g in
                Color.clear.onAppear { textWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in textWidth = w }
            })
    }

    private func run() async {
        offset = 0
        guard needsScroll else { return }
        let distance = textWidth + gap
        let duration = Double(distance) / 30
        while !Task.isCancelled {
            offset = 0
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
        }
    }
}
