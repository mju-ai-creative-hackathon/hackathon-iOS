import SwiftUI

struct RootTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            switch store.selectedTab {
            case .home: HomeView()
            case .create: CreateView()
            case .reels: ReelsView()
            case .tour: TourView()
            case .more: MoreView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        // 다른 화면의 '릴스 만들기' 버튼 → 만들기 탭으로
        .onChange(of: store.isCreatingReel) { _, go in
            if go { store.selectedTab = .create; store.isCreatingReel = false }
        }
    }

    private func info(_ tab: AppTab) -> (icon: String, onIcon: String, title: String) {
        switch tab {
        case .home: ("house", "house.fill", "홈")
        case .create: ("camera", "camera.fill", "만들기")
        case .reels: ("bubble.left", "bubble.left.fill", "커뮤니티")
        case .tour: ("mappin.and.ellipse", "mappin.and.ellipse", "탐색하기")
        case .more: ("line.3.horizontal", "line.3.horizontal", "더보기")
        }
    }

    private var tabBar: some View {
        let dark = store.selectedTab == .reels
        return VStack(spacing: 0) {
            Rectangle().fill(dark ? Color.white.opacity(0.12) : Theme.line).frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    let on = store.selectedTab == tab
                    let i = info(tab)
                    Button { store.selectedTab = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: on ? i.onIcon : i.icon)
                                .font(.system(size: 20, weight: on ? .semibold : .regular))
                                .frame(height: 24)
                            Text(i.title).font(.system(size: 10, weight: on ? .bold : .medium))
                        }
                        .foregroundStyle(on ? Theme.red : (dark ? Color.white.opacity(0.75) : Theme.ink))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background((dark ? Color.black : Theme.bg).ignoresSafeArea(edges: .bottom))
    }
}

/// 더보기: 계정 / 로그아웃
struct MoreView: View {
    @Environment(AuthSession.self) private var auth

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(Theme.red.opacity(0.85))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(auth.user?.name ?? "둘러보는 중").font(.system(size: 17, weight: .bold))
                            Text(auth.user?.email ?? "로그인하면 숏폼을 저장·공유할 수 있어요")
                                .font(.system(size: 13)).foregroundStyle(Theme.gray)
                        }
                    }
                    .padding(.vertical, 6)
                }
                if auth.user != nil {
                    Section {
                        NavigationLink { BookmarksView() } label: { Label("내 북마크", systemImage: "bookmark") }
                    }
                    .foregroundStyle(Theme.ink)
                }
                Section {
                    Label("공지사항", systemImage: "megaphone")
                    Label("고객센터", systemImage: "questionmark.circle")
                    Label("이용약관", systemImage: "doc.text")
                }
                .foregroundStyle(Theme.ink)
                Section {
                    if auth.user != nil {
                        Button("로그아웃", role: .destructive) { auth.logout() }
                    } else {
                        Button("로그인 / 회원가입") { auth.logout() }.foregroundStyle(Theme.red)
                    }
                } footer: {
                    Text("설로그 v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                }
                if auth.user != nil {
                    Section {
                        Button {
                            confirmDelete = true
                        } label: {
                            HStack {
                                Text("회원탈퇴")
                                if isDeleting { Spacer(); ProgressView() }
                            }
                        }
                        .foregroundStyle(Theme.gray)
                        .disabled(isDeleting)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("더보기")
            .confirmationDialog("정말 탈퇴할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("탈퇴하기", role: .destructive) { deleteAccount() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("계정과 북마크가 모두 삭제되고 되돌릴 수 없어요.")
            }
            .alert("탈퇴하지 못했어요", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: { Text(deleteError ?? "") }
        }
    }

    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private func deleteAccount() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do { try await auth.deleteAccount() }
            catch { deleteError = (error as? LocalizedError)?.errorDescription ?? "잠시 후 다시 시도해 주세요." }
        }
    }
}
