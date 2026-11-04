import Foundation

/// A listagem inteira de uma loja pra comparação (`AccountComparisonLoader`), página por página.
enum StoreListingFetcher {
    /// Busca sempre fresco (nunca reaproveita `runner.items`, que pode estar desatualizado) e sem
    /// consultar exposição — a comparação não usa. Uma página que falha encerra a listagem como
    /// `.failed` com o que veio até ali; menos produtos que o `total` informado vira `.incomplete`.
    /// A listagem é a vitrine: só produtos publicados.
    /// - Parameter startedAt: a hora da listagem (`StoreListing.listedAt`).
    static func load(
        sellerID: Int,
        client: EnjoeiClientProtocol,
        startedAt: Date = Date(),
        onProgress: @MainActor (_ loaded: Int, _ total: Int) -> Void
    ) async -> StoreListing {
        var products: [EnjoeiProduct] = []
        var seenIDs: Set<Int> = []
        var cursor: String?
        var expected = 0

        while true {
            if Task.isCancelled { return StoreListing(products: products, status: .failed(loaded: products.count, message: "cancelado"), listedAt: startedAt) }
            let page: StoreProductsPage
            do {
                page = try await client.storeProductsPage(sellerID: sellerID, after: cursor)
            } catch {
                return StoreListing(products: products, status: .failed(loaded: products.count, message: describe(error)), listedAt: startedAt)
            }
            let newProducts = page.products.filter { seenIDs.insert($0.id).inserted }
            products.append(contentsOf: newProducts)
            expected = max(expected, page.total)
            onProgress(products.count, max(expected, products.count))

            // Sem cursor novo, sem produto inédito, ou cursor repetido: acabou a loja.
            guard let endCursor = page.endCursor, !newProducts.isEmpty, endCursor != cursor else { break }
            cursor = endCursor
        }
        let shortfall = expected - products.count
        let status: StoreListingStatus = shortfall > PhotoMatchingParameters.listingShortfallTolerance
            ? .incomplete(loaded: products.count, expected: expected)
            : .complete
        return StoreListing(products: products, status: status, listedAt: startedAt)
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
