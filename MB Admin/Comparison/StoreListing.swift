import Foundation

/// A listagem de uma loja como a comparação recebeu: os produtos que vieram e se veio inteira.
nonisolated struct StoreListing: Sendable {
    let products: [EnjoeiProduct]
    let status: StoreListingStatus
}
