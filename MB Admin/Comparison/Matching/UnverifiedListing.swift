import Foundation

/// Um anúncio sem par que não deu pra verificar — nem par, nem "possivelmente ausente".
nonisolated struct UnverifiedListing: Identifiable, Equatable, Sendable {
    let product: EnjoeiProduct
    let reasons: [UnverifiedReason]

    var id: Int { product.id }
}
