import Foundation

/// Um produto inativo, extraído do JSON embutido no HTML da página "à venda → inativos" — vem no
/// atributo `v-bind:product-list` de um `<product-list-wrapper>` (não é HTML pronto nem API à
/// parte; ver `EnjoeiJavaScript.inactiveProductsPage`).
nonisolated struct InactiveProduct: Identifiable, Equatable, Sendable, Codable {
    let id: Int
    /// Mesmo formato de `EnjoeiProduct.path` — sem o prefixo `/p/`, pronto pra `EnjoeiAPI.productURL`.
    let path: String
    let title: String
    let price: Double?
    let photoPublicID: String?
    /// "dd/mm/yyyy" como veio da página — exibido como está, sem reformatar.
    let inactiveSince: String?

    var formattedPrice: String? {
        guard let price else { return nil }
        return price.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    var thumbnailURL: URL? {
        guard let photoPublicID else { return nil }
        return EnjoeiPhoto.url(publicID: photoPublicID, size: .thumbnail)
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, title, price
        case photoPublicID = "photo_public_id"
        case inactiveSince = "inactive_since"
    }
}
