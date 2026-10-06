import Foundation

struct HapticPayload: Codable {
    let type: String
    let intensity: Float
    let sharpness: Float
}
