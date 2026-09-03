import Foundation

/// Busca dos produtos da loja e checagem de exposição — usado tanto pelo carregamento sozinho
/// (`MegaphoneRunner.loadOnly`) quanto pela primeira busca de uma rodada (`MegaphoneRunner.run`).
/// Extensão à parte só por organização (mesmo tipo, `MegaphoneRunner.swift` ficando grande demais
/// pra navegar).
extension MegaphoneRunner {
    func loadAllProducts(sellerID: Int) async throws -> [EnjoeiProduct] {
        var products: [EnjoeiProduct] = []
        var seenIDs: Set<Int> = []
        var cursor: String?

        while true {
            try Task.checkCancellation()
            let page = try await client.storeProductsPage(sellerID: sellerID, after: cursor)
            let newProducts = page.products.filter { seenIDs.insert($0.id).inserted }
            products.append(contentsOf: newProducts)
            phase = .loadingProducts(loaded: products.count, total: max(page.total, products.count))

            // Sem cursor novo, sem produto inédito, ou cursor repetido: acabou a loja.
            guard let endCursor = page.endCursor, !newProducts.isEmpty, endCursor != cursor else {
                return products
            }
            cursor = endCursor
        }
    }

    func loadExposures(productIDs: [Int]) async throws -> [Int: MegaphoneExposure] {
        var exposuresByProductID: [Int: MegaphoneExposure] = [:]
        var checked = 0

        for batch in chunks(of: productIDs, size: exposureBatchSize) {
            try Task.checkCancellation()
            let exposures = try await client.megaphoneExposures(productIDs: batch)
            for exposure in exposures { exposuresByProductID[exposure.productID] = exposure }
            checked += batch.count
            phase = .checkingExposure(checked: checked, total: productIDs.count)
        }
        return exposuresByProductID
    }

    func chunks(of ids: [Int], size: Int) -> [[Int]] {
        stride(from: 0, to: ids.count, by: size).map {
            Array(ids[$0..<min($0 + size, ids.count)])
        }
    }
}
