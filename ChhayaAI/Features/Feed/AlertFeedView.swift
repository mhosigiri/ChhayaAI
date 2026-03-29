import SwiftUI

struct AlertItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let severity: CardSeverity
    let badge: BadgeVariant
    let icon: String
    let time: String
}

struct AlertFeedView: View {
    @Environment(AgentSessionStore.self) private var sessionStore
    @Environment(\.selectedTabBinding) private var selectedTabBinding

    @State private var selectedFilter: AlertFilter = .all
    @State private var searchText = ""
    @State private var selectedAlert: AlertItem?

    /// Static UI samples; live alert copy comes from the assistant above when available.
    private let alerts: [AlertItem] = AlertFeedView.sampleAlerts

    private var filteredAlerts: [AlertItem] {
        alerts.filter { alert in
            switch selectedFilter {
            case .all:      return true
            case .critical: return alert.severity == .critical
            case .active:   return alert.severity == .warning || alert.severity == .info
            case .resolved: return alert.severity == .normal
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            alertList
        }
        .background(ComponentColor.Screen.bg)
        .sheet(item: $selectedAlert) { alert in
            alertDetailSheet(alert)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: Spacing.space3) {
            AppTextField(
                placeholder: "Search alerts...",
                text: $searchText,
                icon: "magnifyingglass"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.space2) {
                    ForEach(AlertFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
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

    private func filterChip(_ filter: AlertFilter) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = filter
            }
        } label: {
            Text(filter.label)
                .textStyle(.captionMedium)
                .foregroundStyle(
                    selectedFilter == filter
                        ? BrandColor.white
                        : SemanticColor.textSecondary
                )
                .padding(.horizontal, Spacing.space3)
                .padding(.vertical, Spacing.space2)
                .background(
                    selectedFilter == filter
                        ? SemanticColor.actionPrimary
                        : SemanticColor.bgTertiary
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alert List

    private var alertList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.space3) {
                backendAssistantCard
                ForEach(filteredAlerts) { alert in
                    alertCard(alert)
                }
            }
            .padding(.horizontal, Spacing.screenPaddingH)
            .padding(.vertical, Spacing.space4)
        }
    }

    @ViewBuilder
    private var backendAssistantCard: some View {
        if let r = sessionStore.lastResponse,
           let alert = r.alertPayload,
           alert.message != nil || r.chatMessage != nil
        {
            InfoCard(severity: .warning) {
                VStack(alignment: .leading, spacing: Spacing.space2) {
                    Text("Assistant — alert")
                        .textStyle(.labelSemibold)
                        .foregroundStyle(SemanticColor.textPrimary)
                    Text(alert.message ?? r.chatMessage ?? "")
                        .textStyle(.body)
                        .foregroundStyle(SemanticColor.textSecondary)
                    if let n = alert.notifiedHelperCount, n > 0 {
                        Text("Helpers notified: \(n)")
                            .textStyle(.caption)
                            .foregroundStyle(SemanticColor.textAccent)
                    }
                }
            }
        } else if let r = sessionStore.lastResponse,
                  (r.responseType == "ALERT" || r.responseType == "EMERGENCY_FLOW"),
                  let msg = r.chatMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !msg.isEmpty
        {
            InfoCard(severity: .critical) {
                VStack(alignment: .leading, spacing: Spacing.space2) {
                    Text("Assistant — \(r.responseType.replacingOccurrences(of: "_", with: " ").lowercased())")
                        .textStyle(.labelSemibold)
                    Text(msg)
                        .textStyle(.body)
                }
            }
        }
    }

    private func alertCard(_ alert: AlertItem) -> some View {
        InfoCard(severity: alert.severity) {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                HStack(spacing: Spacing.space3) {
                    ZStack {
                        Circle()
                            .fill(alert.severity.accentColor.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: alert.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(alert.severity.accentColor)
                    }

                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        HStack {
                            Text(alert.title)
                                .textStyle(.labelBold)
                                .foregroundStyle(SemanticColor.textPrimary)
                            Spacer()
                            StatusBadge(variant: alert.badge)
                        }
                        Text(alert.description)
                            .textStyle(.caption)
                            .foregroundStyle(SemanticColor.textSecondary)
                            .lineLimit(2)
                    }
                }

                HStack {
                    Text(alert.time)
                        .textStyle(.caption)
                        .foregroundStyle(SemanticColor.textSecondary)
                    Spacer()
                    HStack(spacing: Spacing.space2) {
                        Button("Details") {
                            selectedAlert = alert
                        }
                            .textStyle(.captionMedium)
                            .foregroundStyle(SemanticColor.actionPrimary)
                        if alert.severity == .critical {
                            AppButton(
                                title: "Respond",
                                icon: "arrow.right",
                                style: .primary,
                                isFullWidth: false
                            ) {
                                selectedTabBinding?.wrappedValue = .map
                            }
                        }
                    }
                }
            }
        }
    }

    private func alertDetailSheet(_ alert: AlertItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.space4) {
                    InfoCard(severity: alert.severity) {
                        VStack(alignment: .leading, spacing: Spacing.space3) {
                            HStack {
                                Text(alert.title)
                                    .textStyle(.headingMD)
                                    .foregroundStyle(SemanticColor.textPrimary)
                                Spacer()
                                StatusBadge(variant: alert.badge)
                            }
                            Text(alert.description)
                                .textStyle(.body)
                                .foregroundStyle(SemanticColor.textSecondary)
                            Text(alert.time)
                                .textStyle(.caption)
                                .foregroundStyle(SemanticColor.textSecondary)
                        }
                    }

                    if alert.severity == .critical {
                        AppButton(
                            title: "Open Live Map",
                            icon: "map.fill",
                            style: .primary
                        ) {
                            selectedAlert = nil
                            selectedTabBinding?.wrappedValue = .map
                        }
                    } else {
                        AppButton(
                            title: "Open Chat",
                            icon: "bubble.left.fill",
                            style: .secondary
                        ) {
                            selectedAlert = nil
                            selectedTabBinding?.wrappedValue = .chat
                        }
                    }
                }
                .padding(Spacing.screenPaddingH)
            }
            .navigationTitle("Alert Details")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sample Data

    static let sampleAlerts: [AlertItem] = [
        AlertItem(
            id: "a1",
            title: "Multi-Vehicle Collision",
            description: "3 vehicles involved on Highway 9. Multiple injuries reported. 2 ambulances dispatched.",
            severity: .critical,
            badge: .critical,
            icon: "bolt.heart.fill",
            time: "2 min ago"
        ),
        AlertItem(
            id: "a2",
            title: "AMB-2847 En Route",
            description: "Dispatched to 42 Maple Street. ETA: 7 minutes. Traffic is moderate.",
            severity: .info,
            badge: .enRoute,
            icon: "cross.vial.fill",
            time: "15 min ago"
        ),
        AlertItem(
            id: "a3",
            title: "Heavy Traffic Zone",
            description: "Route B through downtown is experiencing delays. Alternate routes recommended.",
            severity: .warning,
            badge: .approaching,
            icon: "exclamationmark.triangle.fill",
            time: "1h ago"
        ),
        AlertItem(
            id: "a4",
            title: "Emergency #EMR-2024-8847",
            description: "Patient safely delivered to City General Hospital. Response time: 6 minutes.",
            severity: .normal,
            badge: .resolved,
            icon: "checkmark.circle.fill",
            time: "2h ago"
        ),
        AlertItem(
            id: "a5",
            title: "Safe Zone Updated",
            description: "Community center at Block D designated as new emergency shelter.",
            severity: .normal,
            badge: .verified,
            icon: "shield.checkered",
            time: "4h ago"
        ),
    ]
}

// MARK: - Filter Enum

enum AlertFilter: String, CaseIterable, Identifiable {
    case all, critical, active, resolved

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "All"
        case .critical: return "Critical"
        case .active:   return "Active"
        case .resolved: return "Resolved"
        }
    }
}

#Preview {
    AlertFeedView()
}
