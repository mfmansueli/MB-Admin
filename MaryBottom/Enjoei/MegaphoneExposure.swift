import Foundation

/// Um item da resposta de `GET /api/megaphones/v2` — só os campos que a aba de desconto usa.
nonisolated struct MegaphoneExposure: Equatable, Sendable, Decodable {
    let productID: Int
    let kind: MegaphoneExposureKind
    /// Preço sugerido (com desconto) pra alcançar exposição máxima, quando aplicável.
    let priceToIncreaseExposure: Double?
    /// Percentual do desconto sugerido, já formatado pelo Enjoei (ex.: `"- 56%"`).
    let discountLabel: String?

    private enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case kind = "exposure"
        case priceToIncreaseExposure = "price_to_increase_exposure"
        case discountLabel = "discount"
    }
}
