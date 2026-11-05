import SwiftUI

/// 생성 진행 + 결과 확인/공유 화면. 루트1·루트2 공용.
struct ReelGenerationView: View {
    let request: ReelGenerationRequest
    var onDone: () -> Void
    /// 취소/돌아가기. nil 이면 dismiss() (모달로 띄운 경우)
    var onCancel: (() -> Void)? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case generating, done(Reel), failed(String) }

    @State private var phase: Phase = .generating
    @State private var current: ReelGenerationRequest
    @State private var progress = GenerationProgress(stage: "준비 중", fraction: 0)
    @State private var runID = 0
    @State private var tipIndex = 0
    @State private var caption = ""
    @State private var location = ""
    @State private var isPublic = true
    @State private var toast: String?

    private static let tips = [
        "AI가 베스트 컷을 고르는 중...", "흔들린 장면은 살짝 빼둘게요", "음악 박자에 맞춰 컷을 자르는 중",
        "가장 예쁜 순서로 배열하는 중", "어울리는 색감을 입히는 중",
    ]

    init(request: ReelGenerationRequest, onDone: @escaping () -> Void, onCancel: (() -> Void)? = nil) {
        self.onCancel = onCancel
        self.request = request
        self.onDone = onDone
        _current = State(initialValue: request)
        _caption = State(initialValue: request.caption)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch phase {
            case .generating: generatingView
            case .done(let reel): doneView(reel)
            case .failed(let msg): failedView(msg)
            }
            if let toast {
                VStack {
                    Spacer()
                    Text(toast).font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.blueDeep))
                        .padding(.bottom, 110)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
            }
        }
        .task(id: runID) { await run() }
        .task(id: runID) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.3)) { tipIndex = (tipIndex + 1) % Self.tips.count }
            }
        }
    }

    // MARK: 생성

    private func run() async {
        phase = .generating
        progress = GenerationProgress(stage: "준비 중", fraction: 0)
        do {
            let reel = try await store.generator.generate(current) { p in progress = p }
            try Task.checkCancellation()
            withAnimation(.spring(duration: 0.4)) { phase = .done(reel) }
        } catch is CancellationError {
            // 취소: 화면 이탈 또는 재시작
        } catch {
            phase = .failed("릴스를 만들지 못했어요. 잠시 후 다시 시도해줘.")
        }
    }

    // MARK: 생성 중

    private var generatingView: some View {
        VStack(spacing: 26) {
            Spacer()
            FloatingThumbs(images: current.media.compactMap(\.thumbnail))
                .frame(height: 280)
            ZStack {
                Circle().stroke(Theme.blue.opacity(0.15), lineWidth: 10)
                Circle().trim(from: 0, to: max(0.01, progress.fraction))
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress.fraction)
                Text("\(Int(progress.fraction * 100))%")
                    .font(Theme.title(24)).foregroundStyle(Theme.blueDeep).monospacedDigit()
            }
            .frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text(progress.stage).font(Theme.title(20)).foregroundStyle(Theme.blueDeep)
                Text(Self.tips[tipIndex]).font(Theme.hand(16)).foregroundStyle(Theme.blueDeep.opacity(0.75))
                    .id(tipIndex).transition(.opacity)
            }
            Spacer()
            Button("취소") { if let onCancel { onCancel() } else { dismiss() } }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.blueDeep.opacity(0.7))
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    // MARK: 완료

    private func doneView(_ reel: Reel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Text("릴스 완성! 🎉").font(Theme.title(24)).foregroundStyle(Theme.blueDeep).padding(.top, 8)
                    preview(reel)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .frame(maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.blue, lineWidth: 3))
                        .shadow(color: Theme.blue.opacity(0.25), radius: 14, y: 8)

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("캡션", text: $caption, axis: .vertical)
                            .lineLimit(1...4).font(Theme.body)
                        Divider()
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            TextField("위치 추가 (선택)", text: $location).font(Theme.body)
                        }
                        Divider()
                        Picker("공개 범위", selection: $isPublic) {
                            Text("전체 공개").tag(true)
                            Text("친구에게만").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    .paperCard()

                    Button { regenerate() } label: {
                        Label("다시 만들기 (다른 스타일)", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.blueDeep)
                    }
                }
                .padding(20)
            }
            VStack(spacing: 10) {
                Button("릴스 공유하기") { share(reel) }.buttonStyle(PrimaryButtonStyle())
                Button { showToast("저장됨") } label: {
                    Label("기기에 저장", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Theme.cream.opacity(0.95))
        }
    }

    @ViewBuilder
    private func preview(_ reel: Reel) -> some View {
        switch reel.content {
        case .slideshow(let images): SlideshowReelView(images: images)
        case .remoteVideo: Color.black.overlay(Image(systemName: "play.fill").foregroundStyle(.white))
        }
    }

    private func regenerate() {
        let all = ReelStyle.allCases
        if let i = all.firstIndex(of: current.style) { current.style = all[(i + 1) % all.count] }
        current.caption = caption
        runID += 1
    }

    private func share(_ reel: Reel) {
        var r = reel
        r.caption = caption
        let loc = location.trimmingCharacters(in: .whitespaces)
        if !loc.isEmpty { r.location = loc }
        store.publishAndShow(r)
        onDone()
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }

    // MARK: 에러

    private func failedView(_ msg: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(Theme.red)
            Text(msg).font(Theme.body).foregroundStyle(Theme.blueDeep).multilineTextAlignment(.center)
            Button("다시 시도") { runID += 1 }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 220)
            Button("돌아가기") { if let onCancel { onCancel() } else { dismiss() } }.foregroundStyle(Theme.blueDeep.opacity(0.7))
            Spacer()
        }
        .padding(24)
    }
}

/// 업로드한 썸네일들이 천천히 돌며 떠다니는 카드 애니메이션
private struct FloatingThumbs: View {
    let images: [UIImage]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let shown = Array(images.prefix(6))
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, img in
                    let a = t * 0.6 + Double(i) * (2 * .pi / Double(max(shown.count, 1)))
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 92, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.paper, lineWidth: 3))
                        .shadow(color: Theme.blue.opacity(0.3), radius: 8, y: 4)
                        .rotationEffect(.degrees(sin(a * 1.3) * 14))
                        .offset(x: cos(a) * 110, y: sin(a) * 50 + sin(t * 1.5 + Double(i)) * 8)
                        .scaleEffect(0.85 + 0.15 * (sin(a) + 1) / 2)
                        .zIndex(sin(a))
                }
                if shown.isEmpty {
                    Image(systemName: "sparkles").font(.system(size: 60)).foregroundStyle(Theme.blue)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
