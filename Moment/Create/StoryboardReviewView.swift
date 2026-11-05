import SwiftUI

/// 숏폼 스토리보드 검토·승인 (phase=AWAITING_REVIEW)
/// 스토리보드는 AI 서버 형식(snake_case) 그대로라 모르는 키는 JSONValue 로 보존해 다시 저장한다.
struct StoryboardReviewView: View {
    let render: ShortformRender
    /// 승인 성공 → phase=RENDERING 인 제작 상태
    var onApproved: (ShortformRender) -> Void

    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    private let api = APIClient.shared

    @State private var current: ShortformRender?
    @State private var version: Int?
    @State private var title = ""
    @State private var originalTitle = ""
    @State private var cuts: [CutDraft] = []
    @State private var warnings: [Note] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isWorking = false
    @State private var regenCut: String?
    @State private var alert: ReviewAlert?
    @State private var regenTask: Task<Void, Never>?

    private static let screenKeys = ["on_screen_text", "screen_text", "caption", "subtitle", "overlay_text"]

    struct Note: Hashable { let location: String?; let message: String }

    struct CutDraft: Identifiable {
        let id: String
        var raw: [String: JSONValue]
        var role: String?
        var imageURL: URL?
        var narration: String
        var originalNarration: String
        var screenKey: String?
        var screenText: String
        var originalScreenText: String
        var edited: Bool { narration != originalNarration || screenText != originalScreenText }
    }

    struct ReviewAlert: Identifiable {
        enum Kind { case warnings, stale, info }
        let id = UUID()
        let kind: Kind
        let title: String
        let message: String
    }

    private var job: ShortformRender { current ?? render }
    private var isEdited: Bool { title != originalTitle || cuts.contains(where: \.edited) }
    private var busy: Bool { isWorking || regenCut != nil || job.reviewBusy == true }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let e = job.reviewError, !e.isEmpty { banner("다시 확인이 필요해요: \(e)", icon: "exclamationmark.circle.fill") }
                    if !warnings.isEmpty {
                        banner(warnings.map { n in [n.location, n.message].compactMap { $0 }.joined(separator: " · ") }
                                .joined(separator: "\n"), icon: "exclamationmark.triangle.fill")
                    }
                    if isLoading && cuts.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let loadError, cuts.isEmpty {
                        VStack(spacing: 12) {
                            Text(loadError).font(.system(size: 13)).foregroundStyle(Theme.gray).multilineTextAlignment(.center)
                            Button("다시 불러오기") { Task { await load() } }
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.red)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        titleField
                        ForEach($cuts) { $cut in cutCard($cut) }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
            bottomBar
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        .onDisappear { regenTask?.cancel() }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
               presenting: alert) { a in
            switch a.kind {
            case .warnings:
                Button("경고 무시하고 진행", role: .destructive) { approve(acceptWarnings: true) }
                Button("취소", role: .cancel) {}
            case .stale:
                Button("불러오기") { Task { await load() } }
            case .info:
                Button("확인", role: .cancel) {}
            }
        } message: { a in Text(a.message) }
    }

    // MARK: - 화면 조각
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("스토리보드 검토").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                if let version { Text("버전 \(version)").font(.system(size: 11)).foregroundStyle(Theme.gray) }
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("제목").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.gray)
            TextField("숏폼 제목", text: $title)
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.paper))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        }
    }

    private func cutCard(_ cut: Binding<CutDraft>) -> some View {
        let c = cut.wrappedValue
        let index = (cuts.firstIndex { $0.id == c.id } ?? 0) + 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CachedImage(url: c.imageURL)
                    .frame(width: 72, height: 96)
                    .background(Theme.line.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("컷 \(index)").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                        if let role = c.role, !role.isEmpty {
                            Text(role).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.blueSoft))
                        }
                        Spacer()
                        Button { regen(c.id) } label: {
                            HStack(spacing: 4) {
                                if regenCut == c.id { ProgressView().controlSize(.mini) }
                                else { Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)) }
                                Text(regenCut == c.id ? "다시 쓰는 중" : "AI 다시 쓰기")
                            }
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .overlay(Capsule().stroke(Theme.red.opacity(0.4)))
                        }
                        .disabled(busy)
                    }
                    Text("나레이션").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.gray)
                    TextField("나레이션", text: cut.narration, axis: .vertical)
                        .font(.system(size: 14)).foregroundStyle(Theme.ink).lineLimit(2...6)
                }
            }
            if c.screenKey != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("화면 자막").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.gray)
                    TextField("화면에 나올 글자", text: cut.screenText, axis: .vertical)
                        .font(.system(size: 14)).foregroundStyle(Theme.ink).lineLimit(1...3)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(c.edited ? Theme.red.opacity(0.5) : Theme.line))
    }

    private func banner(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.orange)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.orange.opacity(0.12)))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if isEdited {
                Button { Task { _ = await save() } } label: {
                    Text("저장").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 84, height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1.5))
                }
                .disabled(busy)
            }
            Button { approve(acceptWarnings: false) } label: {
                HStack(spacing: 6) {
                    if isWorking { ProgressView().tint(.white) }
                    Text("승인하고 영상 만들기")
                }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(busy || cuts.isEmpty ? Theme.gray : Theme.red))
            }
            .disabled(busy || cuts.isEmpty)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        .background(Theme.bg)
    }

    // MARK: - 데이터
    private func load() async {
        isLoading = true; loadError = nil
        defer { isLoading = false }
        do {
            let latest = try? await auth.authorized { try await api.render(projectId: render.projectId, renderId: render.id, token: $0) }
            if let latest { current = latest }
            let sb = try await auth.authorized {
                try await api.storyboard(projectId: render.projectId, renderId: render.id, token: $0)
            }
            apply(sb)
        } catch {
            loadError = message(for: error)
        }
    }

    private func apply(_ sb: JSONValue) {
        version = sb["version"]?.int ?? job.storyboardVersion
        title = sb["title"]?.string ?? ""
        originalTitle = title
        warnings = Self.notes(sb["warnings"])
        let raw = (sb["cuts"]?.array ?? []).compactMap(\.object)
        cuts = raw.enumerated().map { i, o in
            let v = JSONValue.object(o)
            let key = Self.screenKeys.first { k in
                if case .string = o[k] { return true }
                return o[k] == .null && o[k] != nil
            }
            let narration = v["narration"]?.string ?? ""
            let screen = key.flatMap { v[$0]?.string } ?? ""
            let img = v["media"]?["image_url"]?.string ?? v["media"]?["poster_url"]?.string
            return CutDraft(id: v["cut_id"]?.string ?? "cut-\(i)", raw: o, role: v["role"]?.string,
                            imageURL: img.flatMap(URL.init(string:)),
                            narration: narration, originalNarration: narration,
                            screenKey: key, screenText: screen, originalScreenText: screen)
        }
        .sorted { ($0.raw["position"]?.int ?? 0) < ($1.raw["position"]?.int ?? 0) }
    }

    private static func notes(_ v: JSONValue?) -> [Note] {
        (v?.array ?? []).compactMap { w in
            if let s = w.string { return Note(location: nil, message: s) }
            guard let m = w["message"]?.string ?? w["code"]?.string else { return nil }
            return Note(location: w["location"]?.string, message: m)
        }
    }

    /// 수정본 저장 → 새 버전. 성공하면 true
    private func save() async -> Bool {
        guard let version else { return false }
        isWorking = true
        defer { isWorking = false }
        let body: JSONValue = .object([
            "base_version": .number(Double(version)),
            "title": .string(title),
            "cuts": .array(cuts.map { c in
                var o = c.raw
                if o["narration"] != nil || c.narration != c.originalNarration { o["narration"] = .string(c.narration) }
                if let k = c.screenKey { o[k] = .string(c.screenText) }
                return .object(o)
            }),
        ])
        do {
            let r = try await auth.authorized {
                try await api.saveStoryboard(projectId: render.projectId, renderId: render.id, body: body, token: $0)
            }
            if let w = r.warnings { warnings = Self.notes(.array(w)) }
            await load()
            if let v = r.version, (self.version ?? 0) < v { self.version = v }
            return true
        } catch {
            handle(error)
            return false
        }
    }

    private func regen(_ cutId: String) {
        guard !busy else { return }
        regenTask?.cancel()
        regenTask = Task {
            if isEdited { guard await save() else { return } }
            regenCut = cutId
            defer { regenCut = nil }
            let before = version ?? job.storyboardVersion ?? 0
            do {
                let r = try await auth.authorized {
                    try await api.regenStoryboard(projectId: render.projectId, renderId: render.id,
                                                  cutIds: [cutId], fields: ["narration"], token: $0)
                }
                current = r
                let started = Date()
                while Date().timeIntervalSince(started) < 300 {
                    try await Task.sleep(for: .seconds(3))
                    let j = try await auth.authorized {
                        try await api.render(projectId: render.projectId, renderId: render.id, token: $0)
                    }
                    current = j
                    if j.status.isTerminal || !j.isAwaitingReview { break }
                    if j.reviewBusy != true && (j.storyboardVersion ?? 0) > before { break }
                    if j.reviewBusy != true && Date().timeIntervalSince(started) > 30 { break }
                }
                await load()
            } catch is CancellationError {
            } catch {
                handle(error)
            }
        }
    }

    private func approve(acceptWarnings: Bool) {
        guard !busy || acceptWarnings else { return }
        Task {
            if isEdited { guard await save() else { return } }
            guard let version else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                let r = try await auth.authorized {
                    try await api.approveStoryboard(projectId: render.projectId, renderId: render.id,
                                                    version: version, acceptWarnings: acceptWarnings, token: $0)
                }
                onApproved(r)
                dismiss()
            } catch {
                handle(error)
            }
        }
    }

    // MARK: - 오류
    private func handle(_ error: Error) {
        guard let e = error as? APIError else {
            alert = ReviewAlert(kind: .info, title: "잠시 후 다시 시도해 주세요", message: error.localizedDescription)
            return
        }
        switch e.code {
        case "WARNINGS_NOT_ACCEPTED":
            let list = Self.notes(e.details?["warnings"])
            if !list.isEmpty { warnings = list }
            let text = list.map { n in [n.location, n.message].compactMap { $0 }.joined(separator: ": ") }.joined(separator: "\n")
            alert = ReviewAlert(kind: .warnings, title: "확인할 경고가 있어요", message: text.isEmpty ? e.localizedDescription : text)
        case "STALE_BASE_VERSION":
            alert = ReviewAlert(kind: .stale, title: "최신 버전이 있어요", message: "다른 곳에서 수정됐어요. 최신 버전을 불러올게요")
        case "NOT_IN_REVIEW", "STORYBOARD_NOT_READY":
            alert = ReviewAlert(kind: .stale, title: "상태가 바뀌었어요", message: "제작 상태가 바뀌었어요. 다시 불러올게요")
        default:
            alert = ReviewAlert(kind: .info, title: "다시 확인해 주세요", message: message(for: e))
        }
    }

    private func message(for error: Error) -> String {
        guard let e = error as? APIError else { return error.localizedDescription }
        switch e.code {
        case "JOB_IN_PROGRESS": return "AI가 다시 쓰는 중이에요. 끝난 뒤 다시 시도해 주세요."
        case "STORYBOARD_INVALID", "INVALID_REQUEST":
            let issues = Self.notes(e.details?["issues"])
            if issues.isEmpty { return e.localizedDescription }
            return issues.map { n in [n.location, n.message].compactMap { $0 }.joined(separator: ": ") }.joined(separator: "\n")
        case "RENDER_LIMIT_EXCEEDED": return "오늘 만들 수 있는 숏폼 수를 다 썼어요. 내일 다시 시도해 주세요."
        case "AI_UNAVAILABLE": return "AI 서버와 연결이 잠시 끊겼어요. 잠시 후 다시 시도해 주세요."
        default:
            if e.status == 429 { return "요청이 너무 많아요. 잠시 후 다시 시도해 주세요." }
            if e.status == 503 { return "AI 서버와 연결이 잠시 끊겼어요. 잠시 후 다시 시도해 주세요." }
            return e.localizedDescription
        }
    }
}
