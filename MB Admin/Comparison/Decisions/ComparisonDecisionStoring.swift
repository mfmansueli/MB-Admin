import Foundation

/// Onde ficam as revisões manuais de pares.
protocol ComparisonDecisionStoring: AnyObject {
    /// Todas as decisões entre as duas lojas, em qualquer ordem.
    func decisions(betweenSeller sellerA: Int, andSeller sellerB: Int) -> [ComparisonDecision]
    /// Insere ou substitui (corrigir uma decisão é salvar outra pro mesmo par).
    func save(_ decision: ComparisonDecision)
    /// Desfaz: o par volta pra avaliação automática.
    func removeDecision(for pair: ListingPairKey)
}
