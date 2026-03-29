import SwiftUI
import FirebaseCore

@main
struct ChhayaAIApp: App {
    @State private var authService = AuthService()
    @State private var agentAPIClient = AgentAPIClient()
    @State private var agentSessionStore = AgentSessionStore()
    @State private var locationManager = LocationManager()

    init() {
        FirebaseConfiguration.ensureConfigured()
        MapsConfiguration.configureSDKIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isCheckingAuth {
                    launchScreen
                } else if authService.isAuthenticated {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
            .animation(.easeInOut(duration: 0.3), value: authService.isCheckingAuth)
            .environment(authService)
            .environment(agentAPIClient)
            .environment(agentSessionStore)
            .environment(locationManager)
        }
    }

    private var launchScreen: some View {
        ZStack {
            ComponentColor.Screen.bg.ignoresSafeArea()

            VStack(spacing: Spacing.space4) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    SemanticColor.actionPrimary,
                                    SemanticColor.actionPrimary.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "cross.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(BrandColor.white)
                }

                Text("ChhayaAI")
                    .textStyle(.headingXL)
                    .foregroundStyle(SemanticColor.textPrimary)

                ProgressView()
                    .tint(SemanticColor.actionPrimary)
            }
        }
    }
}
