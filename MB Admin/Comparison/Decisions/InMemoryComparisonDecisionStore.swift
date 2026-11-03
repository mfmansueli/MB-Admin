import Foundation

/// `ComparisonDecisionStoring` só em memória — testes e modo de demonstração.
final class InMemoryComparisonDecisionStore: ComparisonDecisionStoring {
    private(set) var stored: [ListingPairKey: ComparisonDecision] = [:]

    init(decisions: [ComparisonDecision] = []) {
        for decision in decisions {
            stored[decision.pairKey] = decision
        }
    }

    func decisions(betweenSeller sellerA: Int, andSeller sellerB: Int) -> [ComparisonDecision] {
        let sellers: Set = [sellerA, sellerB]
        return stored.values.filter { sellers.contains($0.first.sellerID) && sellers.contains($0.second.sellerID) }
    }

    func save(_ decision: ComparisonDecision) {
        stored[decision.pairKey] = decision
    }

    func removeDecision(for pair: ListingPairKey) {
        stored.removeValue(forKey: pair)
    }
}
