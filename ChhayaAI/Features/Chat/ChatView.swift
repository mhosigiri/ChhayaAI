import FirebaseAuth
import SwiftUI
import UIKit

struct ChatView: View {
    @Environment(AuthService.self) private var authService
    @Environment(AgentAPIClient.self) private var agentAPI
    @Environment(AgentSessionStore.self) private var sessionStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.selectedTabBinding) private var selectedTabBinding
    @Environment(\.openURL) private var openURL

    @State private var inputText = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            sender: .agent,
            text: "Welcome to ChhayaAI. Ask anything, or use a quick suggestion below."
        ),
    ]
    @State private var isSending = false
    @State private var errorBanner: String?

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            if let errorBanner {
                Text(errorBanner)
                    .textStyle(.caption)
                    .foregroundStyle(SemanticColor.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenPaddingH)
                    .padding(.vertical, Spacing.space2)
                    .background(SemanticColor.statusError.opacity(0.08))
            }
            messageList
            inputBar
        }
        .background(ComponentColor.Screen.bg)
        .onAppear {
            locationManager.requestWhenInUse()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: Spacing.space3) {
            ZStack {
                Circle()
                    .fill(SemanticColor.bgTinted)
                    .frame(width: 40, height: 40)
                Image(systemName: "cpu")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SemanticColor.actionPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("ChhayaAI Assistant")
                    .textStyle(.labelBold)
                    .foregroundStyle(SemanticColor.textPrimary)
                HStack(spacing: Spacing.space1) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Thinking…")
                            .textStyle(.caption)
                            .foregroundStyle(SemanticColor.textSecondary)
                    } else {
                        Circle()
                            .fill(SemanticColor.statusSuccess)
                            .frame(width: 6, height: 6)
                        Text("Ready")
                            .textStyle(.caption)
                            .foregroundStyle(SemanticColor.statusSuccess)
                    }
                }
            }

            Spacer()

            Menu {
                Button("Clear Chat", systemImage: "trash") {
                    messages = [
                        ChatMessage(
                            sender: .agent,
                            text: "Chat cleared. How can I help?"
                        ),
                    ]
                    errorBanner = nil
                }
                Button("Agent Settings", systemImage: "gearshape") {
                    openAppSettings()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SemanticColor.iconSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, Spacing.screenPaddingH)
        .padding(.vertical, Spacing.space3)
        .background(ComponentColor.Card.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SemanticColor.borderDefault)
                .frame(height: 0.5)
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.space4) {
                    agentCapabilities
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, Spacing.screenPaddingH)
                .padding(.vertical, Spacing.space4)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var agentCapabilities: some View {
        VStack(spacing: Spacing.space3) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(SemanticColor.actionPrimary)

            Text("How can I help?")
                .textStyle(.headingMD)
                .foregroundStyle(SemanticColor.textPrimary)

            Text("Ask about the app, safety tips, or location-aware help when you enable location.")
                .textStyle(.body)
                .foregroundStyle(SemanticColor.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.space2) {
                suggestionChip("What does this app do?")
                suggestionChip("I need safety tips")
            }
            HStack(spacing: Spacing.space2) {
                suggestionChip("How do alerts work?")
                suggestionChip("Explain the map")
            }
        }
        .padding(.vertical, Spacing.space6)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .textStyle(.captionMedium)
                .foregroundStyle(SemanticColor.actionPrimary)
                .padding(.horizontal, Spacing.space3)
                .padding(.vertical, Spacing.space2)
                .background(SemanticColor.actionPrimary.opacity(0.08))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(SemanticColor.actionPrimary.opacity(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SemanticColor.borderDefault)
                .frame(height: 0.5)

            HStack(spacing: Spacing.space3) {
                AppTextField(
                    placeholder: "Type a message...",
                    text: $inputText,
                    trailingIcon: inputText.isEmpty ? nil : "arrow.up",
                    isPill: true,
                    onTrailingAction: sendMessage,
                    onSubmit: sendMessage
                )
                .disabled(isSending)
            }
            .padding(.horizontal, Spacing.screenPaddingH)
            .padding(.vertical, Spacing.space3)
            .background(ComponentColor.Card.bg)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !isSending else { return }
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMsg = ChatMessage(sender: .user, text: q)
        messages.append(userMsg)
        inputText = ""

        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()

        errorBanner = nil
        isSending = true

        Task { @MainActor in
            let token: String? = await fetchIdToken()
            let pair = locationManager.latLonPair
            do {
                let res = try await agentAPI.sendChat(
                    userId: authService.backendUserId,
                    sessionId: SessionIdentity.sessionId,
                    query: q,
                    lat: pair?.lat,
                    lon: pair?.lon,
                    triggerType: "CHAT",
                    idToken: token
                )
                sessionStore.lastResponse = res
                sessionStore.lastErrorMessage = nil
                if let bind = selectedTabBinding {
                    UIActionRouting.apply(res.uiActions, selectedTab: bind)
                }
                let text = res.chatMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                let reply = (text?.isEmpty == false) ? text! : "No reply from assistant."
                let agentMsg = ChatMessage(sender: .agent, text: reply)
                messages.append(agentMsg)
            } catch {
                sessionStore.lastErrorMessage = error.localizedDescription
                errorBanner = error.localizedDescription
                let fallback = ChatMessage(
                    sender: .agent,
                    text: "Something went wrong reaching the assistant. Check your connection and API URL, then try again."
                )
                messages.append(fallback)
            }
            isSending = false
        }
    }

    private func fetchIdToken() async -> String? {
        await withCheckedContinuation { cont in
            Auth.auth().currentUser?.getIDTokenForcingRefresh(false) { token, _ in
                cont.resume(returning: token)
            } ?? cont.resume(returning: nil)
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview {
    let tab = Binding.constant(AppTab.chat)
    return ChatView()
        .environment(AuthService())
        .environment(AgentAPIClient())
        .environment(AgentSessionStore())
        .environment(LocationManager())
        .environment(\.selectedTabBinding, Optional(tab))
}
