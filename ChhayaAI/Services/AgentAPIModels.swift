import Foundation

// MARK: - Request (matches FastAPI CommonRequest)

struct CommonRequestDTO: Encodable {
    let userId: String
    let sessionId: String
    let query: String?
    let lat: Double?
    let lon: Double?
    let triggerType: String
}

// MARK: - Response (matches CommonResponse + nested payloads)

struct CommonResponseDTO: Decodable {
    let status: String
    let responseType: String
    let chatMessage: String?
    let mapPayload: MapPayloadDTO?
    let alertPayload: AlertPayloadDTO?
    let dataPayload: DataPayloadDTO?
    let uiActions: [String]
}

struct MapPayloadDTO: Decodable {
    let message: String?
    let emergency: Bool?
    let distance: Double?
    let matchStatus: String?
    let matchId: String?
    let matchType: String?
    let requester: MapActorDTO?
    let matchedUser: MapActorDTO?
    let nearbyHelpers: [MapActorDTO]?
    let routeCoordinates: [MapCoordinateDTO]?
}

struct MapActorDTO: Decodable {
    let userId: String?
    let name: String?
    let role: String?
    let lat: Double?
    let lon: Double?
    let distance: Double?
}

struct MapCoordinateDTO: Decodable {
    let lat: Double?
    let lon: Double?
}

struct AlertPayloadDTO: Decodable {
    let alertId: String?
    let message: String?
    let status: String?
    let notifiedHelperCount: Int?
}

struct DataPayloadDTO: Decodable {
    let historyUsed: Bool?
    let contextUsed: Bool?
}

enum AgentAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty { return "Server error (\(code)): \(body)" }
            return "Server error (\(code))."
        case .decoding(let err):
            return "Could not read response: \(err.localizedDescription)"
        }
    }
}
