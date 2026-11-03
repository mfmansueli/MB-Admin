import Foundation

/// Como foi a coleta de uma das lojas — o que a tela mostra no aviso de comparação incompleta.
nonisolated struct ComparisonStoreSummary: Equatable, Sendable {
    let sellerID: Int
    let name: String
    let status: StoreListingStatus
    let listingCount: Int
    /// Anúncios com pelo menos uma foto que não pôde ser analisada.
    let listingsWithPhotoFailures: Int
    /// Anúncios cujo template (todas as fotos) falhou.
    let listingsWithDetailsFailures: Int

    var problems: [String] {
        var problems: [String] = []
        if let listing = status.problemText { problems.append(listing) }
        if listingsWithDetailsFailures > 0 {
            problems.append(listingsWithDetailsFailures == 1
                ? "1 anúncio sem todas as fotos"
                : "\(listingsWithDetailsFailures) anúncios sem todas as fotos")
        }
        if listingsWithPhotoFailures > 0 {
            problems.append(listingsWithPhotoFailures == 1
                ? "1 anúncio com foto que não carregou"
                : "\(listingsWithPhotoFailures) anúncios com foto que não carregou")
        }
        return problems
    }
}
