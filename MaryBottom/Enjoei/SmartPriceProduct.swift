import Foundation

/// Um produto na listagem de "preço esperto" (`GET /api/smart_price/v2` — ver
/// `~/Downloads/enjoeiprecoespertoapi.md`). A API não devolve título nem link do anúncio, só id e
/// preço; quem monta a tela cruza pelo `id` com os produtos já carregados de
/// `MegaphoneRunner.items` pra ter nome e link pra compartilhar (ver `SmartPriceListItem`).
nonisolated struct SmartPriceProduct: Identifiable, Equatable, Sendable, Codable {
    let id: Int
    let price: Double
    let minPrice: Double
    let maxPrice: Double
    /// Se o item está impedido de receber a ação de ativar (campo `blocked` da API).
    let blocked: Bool
    let smartPriceEnabled: Bool
    /// Rótulo colorido que o Enjoei já calcula pra cada anúncio (ex.: "preço alto, venda lenta").
    let statusText: String?
    /// Cor do rótulo, em hex (ex.: `"#FF4D00"`) — ver `Color.init(hex:)`.
    let statusColor: String?
    let photoPublicID: String?

    var formattedPrice: String {
        price.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    var formattedMinPrice: String {
        minPrice.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    var formattedMaxPrice: String {
        maxPrice.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    var thumbnailURL: URL? {
        guard let photoPublicID else { return nil }
        return EnjoeiPhoto.url(publicID: photoPublicID, size: .thumbnail)
    }

    /// Versão maior da foto, pra quando o usuário toca na miniatura pra ver melhor.
    var largePhotoURL: URL? {
        guard let photoPublicID else { return nil }
        return EnjoeiPhoto.url(publicID: photoPublicID, size: .card)
    }

    private struct Description: Codable {
        let color: String?
        let text: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id, price, blocked, description
        case minPrice = "min_price"
        case maxPrice = "max_price"
        case smartPriceEnabled = "smart_price_enabled"
        case photoPublicID = "image_public_id"
    }

    /// Decoder próprio só por causa de `description.text`/`description.color`, aninhados no JSON
    /// mas achatados aqui em `statusText`/`statusColor`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        price = try container.decode(Double.self, forKey: .price)
        minPrice = try container.decode(Double.self, forKey: .minPrice)
        maxPrice = try container.decode(Double.self, forKey: .maxPrice)
        blocked = try container.decode(Bool.self, forKey: .blocked)
        smartPriceEnabled = try container.decode(Bool.self, forKey: .smartPriceEnabled)
        photoPublicID = try container.decodeIfPresent(String.self, forKey: .photoPublicID)
        let description = try container.decodeIfPresent(Description.self, forKey: .description)
        statusText = description?.text
        statusColor = description?.color
    }

    /// Simétrico ao decoder acima — reencaixa `statusText`/`statusColor` em `description`, pra
    /// persistir em disco no mesmo formato que veio do servidor.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(price, forKey: .price)
        try container.encode(minPrice, forKey: .minPrice)
        try container.encode(maxPrice, forKey: .maxPrice)
        try container.encode(blocked, forKey: .blocked)
        try container.encode(smartPriceEnabled, forKey: .smartPriceEnabled)
        try container.encodeIfPresent(photoPublicID, forKey: .photoPublicID)
        if statusText != nil || statusColor != nil {
            try container.encode(Description(color: statusColor, text: statusText), forKey: .description)
        }
    }

    /// Pros testes montarem valores prontos sem passar pelo JSON aninhado.
    init(
        id: Int,
        price: Double,
        minPrice: Double,
        maxPrice: Double,
        blocked: Bool,
        smartPriceEnabled: Bool,
        statusText: String?,
        statusColor: String?,
        photoPublicID: String?
    ) {
        self.id = id
        self.price = price
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.blocked = blocked
        self.smartPriceEnabled = smartPriceEnabled
        self.statusText = statusText
        self.statusColor = statusColor
        self.photoPublicID = photoPublicID
    }
}
