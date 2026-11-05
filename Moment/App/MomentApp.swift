import SwiftUI
import GoogleSignIn

@main
struct MomentApp: App {
    @State private var store = AppStore()
    @State private var auth = AuthSession()
    @State private var places = PlacesStore()
    @State private var community = CommunityStore()
    @State private var tour = TourStore()

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.state {
                case .checking:
                    SplashView()
                case .signedOut:
                    AuthView().transition(.opacity)
                case .signedIn, .guest:
                    RootTabView().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: auth.state)
            .task { places.attach(auth); community.attach(auth); tour.attach(auth); await auth.restore() }
            .onChange(of: auth.state) { _, _ in Task { await places.reloadForAuthChange(); await community.reload(); tour.clearRecommendations(); await tour.loadCourses() } }
            .environment(store).environment(auth).environment(places).environment(community).environment(tour)
        }
    }
}

/// 온보딩(스플래시): 오프화이트 배경 + 가운데 워드마크
private struct SplashView: View {
    var body: some View {
        BrandLogo(size: 34, showEnglish: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
    }
}
