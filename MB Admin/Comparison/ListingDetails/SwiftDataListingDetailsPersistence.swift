import Foundation
import SwiftData

/// `ProductListingDetailsPersisting` no arquivo da própria conta (`PerAccountModelContainer`) —
/// apagado junto com o resto no logout.
final class SwiftDataListingDetailsPersistence: ProductListingDetailsPersisting {
    private let context: ModelContext
    private static let chunkSize = 400

    init(accountID: EnjoeiAccountID) {
        context = ModelContext(PerAccountModelContainer.shared(for: accountID))
    }

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func details(for productIDs: [Int]) -> [Int: ProductListingDetails] {
        var result: [Int: ProductListingDetails] = [:]
        let ids = Array(Set(productIDs))
        for start in stride(from: 0, to: ids.count, by: Self.chunkSize) {
            let chunk = Array(ids[start..<min(start + Self.chunkSize, ids.count)])
            let descriptor = FetchDescriptor<ProductListingDetailsRecord>(predicate: #Predicate { chunk.contains($0.productID) })
            for record in (try? context.fetch(descriptor)) ?? [] {
                result[record.productID] = record.details
            }
        }
        return result
    }

    func upsert(_ details: ProductListingDetails) {
        let productID = details.productID
        var descriptor = FetchDescriptor<ProductListingDetailsRecord>(predicate: #Predicate { $0.productID == productID })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.update(from: details)
        } else {
            context.insert(ProductListingDetailsRecord(details: details))
        }
        try? context.save()
    }

    /// Registro por registro, não `delete(model:)`: a exclusão em lote vai direto no arquivo e os
    /// registros que este contexto já carregou continuavam voltando nas buscas.
    func removeAll() {
        for record in (try? context.fetch(FetchDescriptor<ProductListingDetailsRecord>())) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }

    var count: Int {
        (try? context.fetchCount(FetchDescriptor<ProductListingDetailsRecord>())) ?? 0
    }
}
