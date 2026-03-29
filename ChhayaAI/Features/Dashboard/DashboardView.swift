import CoreLocation
import FirebaseAuth
import MessageUI
import SwiftUI
import UIKit

private struct DashboardBannerState {
    enum Tone {
        case success
        case error
    }

    let message: String
    let tone: Tone
}

private enum LiveLocationAction: Equatable {
    case contacts
    case nearbyUsers
    case emergencyServices
    case specificIndividuals
}

struct DashboardView: View {
    @Environment(AuthService.self) private var authService
    @Environment(AgentAPIClient.self) private var agentAPI
    @Environment(AgentSessionStore.self) private var sessionStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.openURL) private var openURL

    @Binding var selectedTab: AppTab

    @State private var showingSOSConfirmation = false
    @State private var showingEmergencyOptions = false
    @State private var sosBusy = false
    @State private var activeAction: LiveLocationAction?
    @State private var bannerState: DashboardBannerState?

    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    @State private var showingSpecificRecipientsSheet = false
    @State private var specificRecipientsText = ""
    @State private var specificRecipientsContext = ""

    @State private var messageRecipients: [String] = []
    @State private var messageBody = ""
    @State private var showingMessageComposer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.space6) {
                greetingSection
                if let bannerState {
                    feedbackBanner(bannerState)
                }
                activeAlertBanner
                liveLocationSection
                quickNavigationSection
                nearbyUnitsSection
                recentActivitySection
            }
            .padding(.horizontal, Spacing.screenPaddingH)
            .padding(.top, Spacing.space4)
            .padding(.bottom, Spacing.space12)
        }
        .background(ComponentColor.Screen.bg)
        .onAppear {
            locationManager.requestWhenInUse()
        }
        .confirmationDialog(
            "Confirm SOS",
            isPresented: $showingSOSConfirmation,
            titleVisibility: .visible
        ) {
            Button("Send emergency request", role: .destructive) {
                Task { await runEmergencyFlow(call911AfterDispatch: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends your current location through ChhayaAI. Use only for real emergencies.")
        }
        .confirmationDialog(
            "Emergency Dispatch",
            isPresented: $showingEmergencyOptions,
            titleVisibility: .visible
        ) {
            Button("Dispatch through ChhayaAI", role: .destructive) {
                Task { await runEmergencyFlow(call911AfterDispatch: false) }
            }
            Button("Dispatch and call 911", role: .destructive) {
                Task { await runEmergencyFlow(call911AfterDispatch: true) }
            }
            Button("Call 911 only") {
                call911()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ChhayaAI can send your live location through the app. Direct police or ambulance dispatch requires your local emergency services flow.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showingSpecificRecipientsSheet) {
            specificRecipientsSheet
        }
        .sheet(isPresented: $showingMessageComposer) {
            MessageComposerSheet(recipients: messageRecipients, body: messageBody) {
                showingMessageComposer = false
            }
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(greetingText)
                .textStyle(.headingLG)
                .foregroundStyle(SemanticColor.textPrimary)
            Text("ChhayaAI Emergency Response")
                .textStyle(.body)
                .foregroundStyle(SemanticColor.textSecondary)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = authService.displayName
        switch hour {
        case 5..<12:  return "Good Morning, \(name)"
        case 12..<17: return "Good Afternoon, \(name)"
        default:      return "Good Evening, \(name)"
        }
    }

    // MARK: - Banner

    private func feedbackBanner(_ state: DashboardBannerState) -> some View {
        let tint = state.tone == .error ? SemanticColor.statusError : SemanticColor.statusSuccess
        return Text(state.message)
            .textStyle(.caption)
            .foregroundStyle(tint)
            .padding(Spacing.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Active Alert

    private var activeAlertBanner: some View {
        InfoCard(severity: .info) {
            HStack(spacing: Spacing.space3) {
                ZStack {
                    Circle()
                        .fill(SemanticColor.statusSuccess.opacity(AppOpacity.overlaySubtle))
                        .frame(width: 48, height: 48)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SemanticColor.statusSuccess)
                }

                VStack(alignment: .leading, spacing: Spacing.space1) {
                    HStack {
                        Text("System Status")
                            .textStyle(.labelSemibold)
                            .foregroundStyle(SemanticColor.textPrimary)
                        Spacer()
                        StatusBadge(variant: .active)
                    }
                    Text(statusBlurb)
                        .textStyle(.caption)
                        .foregroundStyle(SemanticColor.textSecondary)
                }
            }
        }
    }

    private var statusBlurb: String {
        if let last = sessionStore.lastResponse?.chatMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !last.isEmpty {
            return last
        }
        return "All services operational. Location sharing is ready once device location is enabled."
    }

    // MARK: - Live Location

    private var liveLocationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            Text("Live Location Sharing")
                .textStyle(.headingMD)
                .foregroundStyle(SemanticColor.textPrimary)

            sosButton

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.space3), GridItem(.flexible(), spacing: Spacing.space3)],
                spacing: Spacing.space3
            ) {
                liveLocationButton(
                    action: .contacts,
                    icon: "person.2.fill",
                    title: "Send To Contacts",
                    subtitle: "Open the native share sheet with your live location."
                ) {
                    shareToContacts()
                }

                liveLocationButton(
                    action: .nearbyUsers,
                    icon: "dot.radiowaves.left.and.right",
                    title: "Send Nearby",
                    subtitle: "Notify nearby ChhayaAI users through the backend."
                ) {
                    Task { await shareToNearbyUsers() }
                }

                liveLocationButton(
                    action: .emergencyServices,
                    icon: "cross.case.fill",
                    title: "Police / 911",
                    subtitle: "Dispatch through ChhayaAI and optionally call 911."
                ) {
                    bannerState = nil
                    showingEmergencyOptions = true
                }

                liveLocationButton(
                    action: .specificIndividuals,
                    icon: "person.crop.circle.badge.plus",
                    title: "Specific People",
                    subtitle: "Enter numbers and open Messages with your live location."
                ) {
                    prepareSpecificRecipientsFlow()
                }
            }
        }
    }

    private var sosButton: some View {
        Button {
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.impactOccurred()
            bannerState = nil
            showingSOSConfirmation = true
        } label: {
            HStack(spacing: Spacing.space3) {
                ZStack {
                    Circle()
                        .fill(BrandColor.white.opacity(0.2))
                        .frame(width: 48, height: 48)
                    if sosBusy {
                        ProgressView()
                            .tint(BrandColor.white)
                    } else {
                        Image(systemName: "cross.circle.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(BrandColor.white)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOS Emergency")
                        .textStyle(.headingMD)
                        .foregroundStyle(BrandColor.white)
                    Text("Tap to contact ChhayaAI with your live location")
                        .textStyle(.caption)
                        .foregroundStyle(BrandColor.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BrandColor.white.opacity(0.6))
            }
            .padding(Spacing.space4)
            .background(
                LinearGradient(
                    colors: [SemanticColor.statusError, SemanticColor.statusError.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(sosBusy)
    }

    private func liveLocationButton(
        action: LiveLocationAction,
        icon: String,
        title: String,
        subtitle: String,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(SemanticColor.actionPrimary.opacity(AppOpacity.overlaySubtle))
                            .frame(width: 44, height: 44)
                        if activeAction == action {
                            ProgressView()
                                .tint(SemanticColor.actionPrimary)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(SemanticColor.actionPrimary)
                        }
                    }
                    Spacer()
                }

                Text(title)
                    .textStyle(.labelBold)
                    .foregroundStyle(SemanticColor.textPrimary)

                Text(subtitle)
                    .textStyle(.caption)
                    .foregroundStyle(SemanticColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
            .padding(Spacing.space4)
            .background(ComponentColor.Card.bg)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            .appShadow(.card)
        }
        .buttonStyle(.plain)
        .disabled(sosBusy || activeAction != nil)
    }

    // MARK: - Navigation

    private var quickNavigationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            Text("Navigate")
                .textStyle(.headingMD)
                .foregroundStyle(SemanticColor.textPrimary)

            HStack(spacing: Spacing.space3) {
                AppButton(
                    title: "Open Live Map",
                    icon: "map.fill",
                    style: .secondary
                ) {
                    selectedTab = .map
                }

                AppButton(
                    title: "AI Assistant",
                    icon: "bubble.left.fill",
                    style: .outline
                ) {
                    selectedTab = .chat
                }
            }
        }
    }

    // MARK: - Nearby Units

    private var nearbyUnitsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            HStack {
                Text("Nearby Units")
                    .textStyle(.headingMD)
                    .foregroundStyle(SemanticColor.textPrimary)
                Spacer()
                Button("Open map") {
                    selectedTab = .map
                }
                .textStyle(.labelSemibold)
                .foregroundStyle(SemanticColor.actionPrimary)
            }

            InfoCard {
                VStack(alignment: .leading, spacing: Spacing.space2) {
                    if let matchedUser = sessionStore.lastResponse?.mapPayload?.matchedUser {
                        Text(matchedUser.name ?? "Nearby support located")
                            .textStyle(.labelBold)
                            .foregroundStyle(SemanticColor.textPrimary)
                        Text(matchedUser.role ?? "Matched user")
                            .textStyle(.caption)
                            .foregroundStyle(SemanticColor.textSecondary)
                    } else {
                        Text("Live matches come from the map agent when location is enabled.")
                            .textStyle(.body)
                            .foregroundStyle(SemanticColor.textSecondary)
                    }

                    Button("Go to map tab") {
                        selectedTab = .map
                    }
                    .textStyle(.labelSemibold)
                    .foregroundStyle(SemanticColor.actionPrimary)
                }
            }
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            HStack {
                Text("Recent Activity")
                    .textStyle(.headingMD)
                    .foregroundStyle(SemanticColor.textPrimary)
                Spacer()
                Button("Chat") {
                    selectedTab = .chat
                }
                .textStyle(.labelSemibold)
                .foregroundStyle(SemanticColor.actionPrimary)
            }

            if let last = sessionStore.lastResponse?.chatMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !last.isEmpty {
                activityRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: SemanticColor.actionPrimary,
                    title: "Last assistant reply",
                    subtitle: last,
                    time: "Just now"
                )
            } else {
                activityRow(
                    icon: "clock.fill",
                    iconColor: SemanticColor.textSecondary,
                    title: "No recent activity",
                    subtitle: "Open AI Agent to start a conversation.",
                    time: ""
                )
            }
        }
    }

    private func activityRow(icon: String, iconColor: Color, title: String, subtitle: String, time: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.space3) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Spacing.space1) {
                Text(title)
                    .textStyle(.labelSemibold)
                    .foregroundStyle(SemanticColor.textPrimary)
                Text(subtitle)
                    .textStyle(.caption)
                    .foregroundStyle(SemanticColor.textSecondary)
                    .lineLimit(4)
            }

            Spacer()

            if !time.isEmpty {
                Text(time)
                    .textStyle(.caption)
                    .foregroundStyle(SemanticColor.textSecondary)
            }
        }
        .padding(Spacing.space4)
        .background(ComponentColor.Card.bg)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Sheets

    private var specificRecipientsSheet: some View {
        NavigationStack {
            Form {
                Section("Recipients") {
                    TextField("Comma-separated phone numbers", text: $specificRecipientsText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)

                    Text("Example: +13125550100, +13125550101")
                        .font(.caption)
                        .foregroundStyle(SemanticColor.textSecondary)
                }

                Section("Optional Context") {
                    TextField("Add a short note", text: $specificRecipientsContext, axis: .vertical)
                }
            }
            .navigationTitle("Specific Individuals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showingSpecificRecipientsSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        sendToSpecificIndividuals()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Sharing Actions

    private func shareToContacts() {
        guard let coordinate = currentCoordinate() else { return }
        bannerState = nil
        activeAction = .contacts
        shareItems = [
            LiveLocationShareFormatter.shareMessage(
                senderName: authService.displayName,
                coordinate: coordinate,
                context: "Emergency contacts"
            )
        ]
        showingShareSheet = true
        activeAction = nil
    }

    private func prepareSpecificRecipientsFlow() {
        guard currentCoordinate() != nil else { return }
        bannerState = nil
        specificRecipientsContext = ""
        specificRecipientsText = ""
        showingSpecificRecipientsSheet = true
    }

    private func sendToSpecificIndividuals() {
        let recipients = specificRecipientsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !recipients.isEmpty else {
            bannerState = DashboardBannerState(
                message: "Enter at least one phone number to send your live location.",
                tone: .error
            )
            return
        }
        guard let coordinate = currentCoordinate() else { return }

        let context = specificRecipientsContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Specific individuals"
            : specificRecipientsContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = LiveLocationShareFormatter.shareMessage(
            senderName: authService.displayName,
            coordinate: coordinate,
            context: context
        )

        showingSpecificRecipientsSheet = false
        activeAction = .specificIndividuals
        presentMessageFlow(recipients: recipients, body: body)
    }

    private func shareToNearbyUsers() async {
        await MainActor.run {
            bannerState = nil
            activeAction = .nearbyUsers
        }

        let token: String? = await withCheckedContinuation { cont in
            Auth.auth().currentUser?.getIDTokenForcingRefresh(false) { token, _ in
                cont.resume(returning: token)
            } ?? cont.resume(returning: nil)
        }

        guard let pair = locationManager.latLonPair else {
            await MainActor.run {
                activeAction = nil
                bannerState = DashboardBannerState(
                    message: "Location required. Enable location services and try again.",
                    tone: .error
                )
            }
            return
        }

        do {
            let res = try await agentAPI.sendChat(
                userId: authService.backendUserId,
                sessionId: SessionIdentity.sessionId,
                query: "Share my live location with nearby users",
                lat: pair.lat,
                lon: pair.lon,
                triggerType: "SHARE_TO_NEARBY",
                idToken: token
            )

            await MainActor.run {
                sessionStore.lastResponse = res
                sessionStore.lastErrorMessage = nil
                activeAction = nil
                let message = res.alertPayload?.message
                    ?? res.chatMessage
                    ?? "Nearby users have been notified."
                bannerState = DashboardBannerState(message: message, tone: .success)
                UIActionRouting.apply(res.uiActions, selectedTab: $selectedTab)
            }
        } catch {
            await MainActor.run {
                sessionStore.lastErrorMessage = error.localizedDescription
                activeAction = nil
                bannerState = DashboardBannerState(message: error.localizedDescription, tone: .error)
            }
        }
    }

    private func presentMessageFlow(recipients: [String], body: String) {
        if MFMessageComposeViewController.canSendText() {
            messageRecipients = recipients
            messageBody = body
            showingMessageComposer = true
            activeAction = nil
            return
        }

        shareItems = [body]
        showingShareSheet = true
        activeAction = nil
        bannerState = DashboardBannerState(
            message: "Messages is unavailable on this device. Opened the share sheet instead.",
            tone: .success
        )
    }

    private func currentCoordinate() -> CLLocationCoordinate2D? {
        guard let pair = locationManager.latLonPair else {
            bannerState = DashboardBannerState(
                message: "Location required. Enable location services and try again.",
                tone: .error
            )
            return nil
        }
        return CLLocationCoordinate2D(latitude: pair.lat, longitude: pair.lon)
    }

    // MARK: - Emergency

    private func runEmergencyFlow(call911AfterDispatch: Bool) async {
        await MainActor.run {
            sosBusy = true
            bannerState = nil
        }

        let token: String? = await withCheckedContinuation { cont in
            Auth.auth().currentUser?.getIDTokenForcingRefresh(false) { token, _ in
                cont.resume(returning: token)
            } ?? cont.resume(returning: nil)
        }

        let pair = locationManager.latLonPair
        guard let pair else {
            await MainActor.run {
                sosBusy = false
                bannerState = DashboardBannerState(
                    message: "Location required. Enable location services and try again.",
                    tone: .error
                )
            }
            return
        }

        do {
            let res = try await agentAPI.sendChat(
                userId: authService.backendUserId,
                sessionId: SessionIdentity.sessionId,
                query: "Emergency button pressed",
                lat: pair.lat,
                lon: pair.lon,
                triggerType: "EMERGENCY_BUTTON",
                idToken: token
            )
            await MainActor.run {
                sessionStore.lastResponse = res
                sessionStore.lastErrorMessage = nil
                sosBusy = false
                bannerState = DashboardBannerState(
                    message: res.chatMessage ?? "Emergency request sent.",
                    tone: .success
                )
                UIActionRouting.apply(res.uiActions, selectedTab: $selectedTab)
            }
            if call911AfterDispatch {
                await MainActor.run {
                    call911()
                }
            }
        } catch {
            await MainActor.run {
                sessionStore.lastErrorMessage = error.localizedDescription
                sosBusy = false
                bannerState = DashboardBannerState(message: error.localizedDescription, tone: .error)
            }
        }
    }

    private func call911() {
        guard let url = URL(string: "tel://911") else { return }
        openURL(url) { accepted in
            if !accepted {
                bannerState = DashboardBannerState(
                    message: "Calling 911 is only available on a real phone with calling support.",
                    tone: .error
                )
            }
        }
    }
}

#Preview {
    DashboardView(selectedTab: .constant(.dashboard))
        .environment(AuthService())
        .environment(AgentAPIClient())
        .environment(AgentSessionStore())
        .environment(LocationManager())
}
