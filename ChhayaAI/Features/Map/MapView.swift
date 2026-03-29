import CoreLocation
import FirebaseAuth
import Foundation
import GoogleMaps
import SwiftUI

private struct LiveMapMarker: Identifiable, Hashable {
    enum Kind {
        case requester
        case matchedUser
        case nearbyUser

        var title: String {
            switch self {
            case .requester:   return "You"
            case .matchedUser: return "Matched User"
            case .nearbyUser:  return "Nearby User"
            }
        }

        var color: UIColor {
            switch self {
            case .requester:   return .systemBlue
            case .matchedUser: return .systemRed
            case .nearbyUser:  return .systemGreen
            }
        }
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let name: String
    let subtitle: String
    let kind: Kind

    static func == (lhs: LiveMapMarker, rhs: LiveMapMarker) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct GoogleLiveMapView: UIViewRepresentable {
    let centerCoordinate: CLLocationCoordinate2D
    let markers: [LiveMapMarker]
    let routeCoordinates: [CLLocationCoordinate2D]
    let cameraRequestID: UUID
    @Binding var selectedMarkerID: String?

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleLiveMapView
        var markerByID: [String: GMSMarker] = [:]
        var lastCameraRequestID: UUID?

        init(parent: GoogleLiveMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            parent.selectedMarkerID = marker.userData as? String
            return false
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selectedMarkerID = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> GMSMapView {
        MapsConfiguration.configureSDKIfNeeded()

        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition.camera(
            withLatitude: centerCoordinate.latitude,
            longitude: centerCoordinate.longitude,
            zoom: 14
        )
        if let mapID = MapsConfiguration.mapID, !mapID.isEmpty {
            options.mapID = GMSMapID(identifier: mapID)
        }

        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        uiView.clear()
        context.coordinator.markerByID = [:]

        if routeCoordinates.count > 1 {
            let path = GMSMutablePath()
            routeCoordinates.forEach { path.add($0) }
            let polyline = GMSPolyline(path: path)
            polyline.strokeColor = .systemBlue
            polyline.strokeWidth = 4
            polyline.geodesic = true
            polyline.map = uiView
        }

        for item in markers {
            let marker = GMSMarker()
            marker.position = item.coordinate
            marker.title = item.name
            marker.snippet = item.subtitle
            marker.userData = item.id
            marker.icon = GMSMarker.markerImage(with: item.kind.color)
            marker.appearAnimation = .pop
            marker.map = uiView
            context.coordinator.markerByID[item.id] = marker
        }

        if let selectedMarkerID,
           let selectedMarker = context.coordinator.markerByID[selectedMarkerID] {
            uiView.selectedMarker = selectedMarker
        } else {
            uiView.selectedMarker = nil
        }

        if context.coordinator.lastCameraRequestID != cameraRequestID {
            focusMap(uiView)
            context.coordinator.lastCameraRequestID = cameraRequestID
        }
    }

    private func focusMap(_ mapView: GMSMapView) {
        if let selectedMarkerID,
           let selectedMarker = markers.first(where: { $0.id == selectedMarkerID }) {
            mapView.animate(toLocation: selectedMarker.coordinate)
            mapView.animate(toZoom: 15)
            return
        }

        let points = routeCoordinates + markers.map(\.coordinate)
        guard let first = points.first else {
            mapView.animate(toLocation: centerCoordinate)
            mapView.animate(toZoom: 14)
            return
        }

        var bounds = GMSCoordinateBounds(coordinate: first, coordinate: first)
        for point in points.dropFirst() {
            bounds = bounds.includingCoordinate(point)
        }
        let update = GMSCameraUpdate.fit(bounds, withPadding: 72)
        mapView.animate(with: update)
    }
}

private extension MapActorDTO {
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        guard (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

private extension MapCoordinateDTO {
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        guard (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct MapTabView: View {
    @Environment(AuthService.self) private var authService
    @Environment(AgentAPIClient.self) private var agentAPI
    @Environment(AgentSessionStore.self) private var sessionStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.openURL) private var openURL

    @State private var selectedMarkerID: String?
    @State private var searchText = ""
    @State private var mapLoading = false
    @State private var mapError: String?
    @State private var lastMapAssistantText: String?
    @State private var cameraRequestID = UUID()

    private let fallbackCenter = CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)

    private var mapPayload: MapPayloadDTO? {
        sessionStore.lastResponse?.mapPayload
    }

    private var centerCoordinate: CLLocationCoordinate2D {
        if let requester = mapPayload?.requester?.coordinate {
            return requester
        }
        if let device = locationManager.coordinate {
            return device
        }
        return fallbackCenter
    }

    private var renderedMarkers: [LiveMapMarker] {
        var markers: [LiveMapMarker] = []
        var seen = Set<String>()

        if let requester = mapPayload?.requester,
           let coordinate = requester.coordinate {
            let id = requester.userId ?? "requester"
            markers.append(
                LiveMapMarker(
                    id: id,
                    coordinate: coordinate,
                    name: "You",
                    subtitle: requester.role?.capitalized ?? "Current location",
                    kind: .requester
                )
            )
            seen.insert(id)
        } else if let coordinate = locationManager.coordinate {
            markers.append(
                LiveMapMarker(
                    id: "device-location",
                    coordinate: coordinate,
                    name: "You",
                    subtitle: "Current location",
                    kind: .requester
                )
            )
            seen.insert("device-location")
        }

        if let matchedUser = mapPayload?.matchedUser,
           let coordinate = matchedUser.coordinate {
            let id = matchedUser.userId ?? "matched-user"
            if !seen.contains(id) {
                markers.append(
                    LiveMapMarker(
                        id: id,
                        coordinate: coordinate,
                        name: matchedUser.name ?? matchedUser.userId ?? "Matched User",
                        subtitle: actorSubtitle(matchedUser, fallback: "Matched user"),
                        kind: .matchedUser
                    )
                )
                seen.insert(id)
            }
        }

        for actor in mapPayload?.nearbyHelpers ?? [] {
            guard let coordinate = actor.coordinate else { continue }
            let id = actor.userId ?? "nearby-\(coordinate.latitude)-\(coordinate.longitude)"
            if seen.contains(id) { continue }
            markers.append(
                LiveMapMarker(
                    id: id,
                    coordinate: coordinate,
                    name: actor.name ?? actor.userId ?? "Nearby User",
                    subtitle: actorSubtitle(actor, fallback: "Nearby user"),
                    kind: .nearbyUser
                )
            )
            seen.insert(id)
        }

        return markers
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        mapPayload?.routeCoordinates?.compactMap(\.coordinate) ?? []
    }

    private var selectedMarker: LiveMapMarker? {
        renderedMarkers.first { $0.id == selectedMarkerID }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if MapsConfiguration.isReady {
                GoogleLiveMapView(
                    centerCoordinate: centerCoordinate,
                    markers: renderedMarkers,
                    routeCoordinates: routeCoordinates,
                    cameraRequestID: cameraRequestID,
                    selectedMarkerID: $selectedMarkerID
                )
                .ignoresSafeArea(edges: .top)
            } else {
                unavailableMapView
                    .ignoresSafeArea(edges: .top)
            }

            VStack(spacing: Spacing.space3) {
                searchBar
                backendBanner
            }
            .padding(.horizontal, Spacing.screenPaddingH)
            .padding(.top, Spacing.space12)

            VStack {
                Spacer()
                if let selectedMarker {
                    markerDetailCard(selectedMarker)
                        .padding(.horizontal, Spacing.screenPaddingH)
                        .padding(.bottom, Spacing.space4)
                }
            }
        }
        .onAppear {
            locationManager.requestWhenInUse()
            cameraRequestID = UUID()
        }
        .onChange(of: locationManager.coordinate?.latitude) {
            if mapPayload?.requester == nil {
                cameraRequestID = UUID()
            }
        }
        .onChange(of: locationManager.coordinate?.longitude) {
            if mapPayload?.requester == nil {
                cameraRequestID = UUID()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await askMapAgent() }
                } label: {
                    if mapLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(mapLoading || !MapsConfiguration.isReady)
                .accessibilityLabel("Refresh live map")
            }
        }
    }

    // MARK: - Header

    private var searchBar: some View {
        AppTextField(
            placeholder: "Search helpers or refresh nearby users...",
            text: $searchText,
            icon: "magnifyingglass",
            trailingIcon: mapLoading ? nil : trailingSearchIcon,
            isPill: false,
            onTrailingAction: handleSearchAction,
            onSubmit: handleSearchAction
        )
        .appShadow(.elevated)
    }

    private var trailingSearchIcon: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "location.fill" : "arrow.up"
    }

    private var backendBanner: some View {
        Group {
            if !MapsConfiguration.isReady {
                bannerText("Google Maps is not configured. Add a valid API key and Map ID in the app settings.")
                    .foregroundStyle(SemanticColor.statusError)
                    .background(SemanticColor.statusError.opacity(0.1))
            } else if let err = mapError {
                bannerText(err)
                    .foregroundStyle(SemanticColor.statusError)
                    .background(SemanticColor.statusError.opacity(0.1))
            } else if let msg = lastMapAssistantText?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                bannerText(msg)
                    .foregroundStyle(SemanticColor.textPrimary)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var unavailableMapView: some View {
        ZStack {
            LinearGradient(
                colors: [SemanticColor.bgTinted, ComponentColor.Screen.bg],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: Spacing.space3) {
                Image(systemName: "map.circle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(SemanticColor.actionPrimary)
                Text("Google Maps Unavailable")
                    .textStyle(.headingMD)
                    .foregroundStyle(SemanticColor.textPrimary)
                Text("The map preview can’t create a Google map until the SDK is initialized with a valid API key.")
                    .textStyle(.body)
                    .foregroundStyle(SemanticColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(Spacing.space6)
        }
    }

    private func bannerText(_ text: String) -> some View {
        Text(text)
            .textStyle(.caption)
            .padding(Spacing.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    private func markerDetailCard(_ marker: LiveMapMarker) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        Text(marker.name)
                            .textStyle(.labelBold)
                            .foregroundStyle(SemanticColor.textPrimary)
                        Text(marker.subtitle)
                            .textStyle(.caption)
                            .foregroundStyle(SemanticColor.textSecondary)
                    }
                    Spacer()
                    Text(marker.kind.title)
                        .textStyle(.captionMedium)
                        .foregroundStyle(SemanticColor.actionPrimary)
                        .padding(.horizontal, Spacing.space3)
                        .padding(.vertical, Spacing.space1_5)
                        .background(SemanticColor.actionPrimary.opacity(0.08))
                        .clipShape(Capsule())
                }

                HStack(spacing: Spacing.space3) {
                    AppButton(
                        title: "Center",
                        icon: "location.fill",
                        style: .secondary,
                        isFullWidth: true
                    ) {
                        selectedMarkerID = marker.id
                        cameraRequestID = UUID()
                    }

                    if marker.kind != .requester {
                        AppButton(
                            title: "Directions",
                            icon: "arrow.triangle.turn.up.right.diamond.fill",
                            style: .outline,
                            isFullWidth: true
                        ) {
                            openDirections(to: marker.coordinate)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func handleSearchAction() {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedMarkerID = nil
            cameraRequestID = UUID()
            return
        }
        Task { await askMapAgent() }
    }

    private func askMapAgent() async {
        guard MapsConfiguration.isReady else {
            await MainActor.run {
                mapError = "Google Maps is not configured for this build."
            }
            return
        }

        await MainActor.run {
            mapError = nil
        }

        let token: String? = await withCheckedContinuation { cont in
            Auth.auth().currentUser?.getIDTokenForcingRefresh(false) { token, _ in
                cont.resume(returning: token)
            } ?? cont.resume(returning: nil)
        }

        let pair = locationManager.latLonPair
        guard let pair else {
            await MainActor.run {
                mapError = "Turn on location to use the live map."
            }
            return
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Find nearby helpers on the live map"
            : searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        await MainActor.run {
            mapLoading = true
        }
        defer {
            Task { @MainActor in
                mapLoading = false
            }
        }

        do {
            let res = try await agentAPI.sendChat(
                userId: authService.backendUserId,
                sessionId: SessionIdentity.sessionId,
                query: query,
                lat: pair.lat,
                lon: pair.lon,
                triggerType: "MAP",
                idToken: token
            )

            let assistantText = [res.chatMessage, res.mapPayload?.message]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }

            await MainActor.run {
                sessionStore.lastResponse = res
                lastMapAssistantText = assistantText
                selectedMarkerID = selectionID(from: res.mapPayload)
                cameraRequestID = UUID()
            }
        } catch {
            await MainActor.run {
                mapError = error.localizedDescription
            }
        }
    }

    private func openDirections(to coordinate: CLLocationCoordinate2D) {
        let lat = String(format: "%.6f", coordinate.latitude)
        let lon = String(format: "%.6f", coordinate.longitude)
        guard let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)") else {
            return
        }
        openURL(url)
    }

    private func actorSubtitle(_ actor: MapActorDTO, fallback: String) -> String {
        let role = actor.role?.replacingOccurrences(of: "_", with: " ").capitalized ?? fallback
        if let distance = actor.distance {
            return "\(role) • \(Int(distance))m away"
        }
        return role
    }

    private func selectionID(from payload: MapPayloadDTO?) -> String? {
        if let matched = payload?.matchedUser {
            return matched.userId ?? "matched-user"
        }
        if let first = payload?.nearbyHelpers?.first {
            return first.userId ?? first.coordinate.map { "nearby-\($0.latitude)-\($0.longitude)" }
        }
        return nil
    }
}

#Preview {
    MapTabView()
        .environment(AuthService())
        .environment(AgentAPIClient())
        .environment(AgentSessionStore())
        .environment(LocationManager())
}
