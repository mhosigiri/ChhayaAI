import Foundation
import GoogleMaps

enum MapsConfiguration {
    private static var didConfigureSDK = false

    static var apiKey: String? {
        value(for: "GOOGLE_MAPS_API_KEY")
    }

    static var mapID: String? {
        value(for: "GOOGLE_MAPS_MAP_ID")
    }

    static var isReady: Bool {
        guard let apiKey, !apiKey.isEmpty else { return false }
        return true
    }

    static func configureSDKIfNeeded() {
        guard !didConfigureSDK else { return }
        guard let apiKey, !apiKey.isEmpty else { return }
        GMSServices.provideAPIKey(apiKey)
        didConfigureSDK = true
    }

    private static func value(for key: String) -> String? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let raw = ProcessInfo.processInfo.environment[key] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
