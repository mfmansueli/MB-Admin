import Foundation
import SwiftData

/// `ComparisonDecisionStoring` em SwiftData, no `SharedModelContainer`. Poucas linhas (só o que o
/// usuário revisou à mão), lidas uma vez por comparação — um contexto próprio no MainActor basta.
/// `ModelContext(container)` (e não `container.mainContext`) segura o container vivo, como nas
/// outras persistências do app.
final class SwiftDataComparisonDecisionStore: ComparisonDecisionStoring {
    private let context: ModelContext

    init(container: ModelContainer = SharedModelContainer.shared) {
        context = ModelContext(container)
    }

    func decisions(betweenSeller sellerA: Int, andSeller sellerB: Int) -> [ComparisonDecision] {
        let descriptor = FetchDescriptor<ComparisonDecisionRecord>(predicate: #Predicate {
            ($0.firstSellerID == sellerA && $0.secondSellerID == sellerB)
                || ($0.firstSellerID == sellerB && $0.secondSellerID == sellerA)
        })
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.decision)
    }

    func save(_ decision: ComparisonDecision) {
        if let existing = record(for: decision.pairKey) {
            existing.update(from: decision)
        } else {
            context.insert(ComparisonDecisionRecord(decision: decision))
        }
        try? context.save()
    }

    func removeDecision(for pair: ListingPairKey) {
        guard let existing = record(for: pair) else { return }
        context.delete(existing)
        try? context.save()
    }

    private func record(for pair: ListingPairKey) -> ComparisonDecisionRecord? {
        let pairID = pair.storageID
        var descriptor = FetchDescriptor<ComparisonDecisionRecord>(predicate: #Predicate { $0.pairID == pairID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
