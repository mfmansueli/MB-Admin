import Foundation

/// O que precisa continuar igual num anúncio pra uma revisão manual feita antes ainda valer: a capa
/// (id público da foto) e o título normalizado. Mudou qualquer um dos dois, a revisão fica
/// "desatualizada" — não é aplicada, o par volta pra avaliação automática e a tela avisa.
///
/// Limitação conhecida: trocar só uma foto que não é a capa não invalida a revisão.
nonisolated struct ListingFingerprint: Equatable, Sendable, Codable {
    let coverPublicID: String?
    let normalizedTitle: String

    init(coverPublicID: String?, normalizedTitle: String) {
        self.coverPublicID = coverPublicID
        self.normalizedTitle = normalizedTitle
    }

    init(product: EnjoeiProduct) {
        coverPublicID = product.photoPublicID
        normalizedTitle = ProductSimilarity.tokenize(product.title).sorted().joined(separator: " ")
    }
}
