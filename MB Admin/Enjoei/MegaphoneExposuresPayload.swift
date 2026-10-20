import Foundation

/// Envelope de `GET /api/megaphones/v2` — o resto do corpo (`messages`, `smart_price_content`) não
/// é usado pelo app.
nonisolated struct MegaphoneExposuresPayload: Equatable, Sendable, Decodable {
    let products: [MegaphoneExposure]
}
