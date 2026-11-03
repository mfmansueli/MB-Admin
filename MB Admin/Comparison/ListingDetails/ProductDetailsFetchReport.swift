import Foundation

/// O que uma rodada de `ProductDetailsLoader.fetchDetails` conseguiu: o template de cada anúncio que
/// respondeu, o motivo de cada um que falhou, e se a rodada foi interrompida antes do fim (aí os que
/// faltaram não estão em nenhum dos dois).
nonisolated struct ProductDetailsFetchReport: Sendable {
    var details: [Int: ProductListingDetails] = [:]
    var failures: [Int: String] = [:]
    var wasCancelled = false
}
