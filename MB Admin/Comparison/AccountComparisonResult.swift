import Foundation

/// Resultado de comparar duas lojas, em quatro estados que nunca se confundem:
/// - `matches`: correspondência forte (mesma foto, sem concorrente) ou confirmada por você;
/// - `reviews`: precisa revisar — há indício, mas não dá pra concluir sozinho;
/// - `possiblyMissingInB`/`possiblyMissingInA`: nenhum indício na outra loja, com tudo dos dois
///   lados analisado e a lista da outra loja completa;
/// - `unverifiedA`/`unverifiedB`: sem par, mas algo impediu a verificação — nunca é "ausente".
///
/// `rejected` são os pares que você marcou como produtos diferentes (pra poder desfazer).
nonisolated struct AccountComparisonResult: Equatable, Sendable {
    /// Da rodada de comparação — não muda quando uma revisão manual recalcula o resultado (só
    /// `revision`), pra tela não perder busca/filtro a cada decisão. Comparar de novo gera outro.
    let id: UUID
    let revision: Int
    let storeA: ComparisonStoreSummary
    let storeB: ComparisonStoreSummary
    let matches: [ProductMatch]
    let reviews: [ProductMatch]
    let rejected: [ProductMatch]
    /// Produtos de A sem nenhum indício em B.
    let possiblyMissingInB: [EnjoeiProduct]
    /// Produtos de B sem nenhum indício em A.
    let possiblyMissingInA: [EnjoeiProduct]
    let unverifiedA: [UnverifiedListing]
    let unverifiedB: [UnverifiedListing]
    /// Revisões manuais que deixaram de valer porque um dos anúncios mudou.
    let staleDecisionCount: Int

    init(
        id: UUID = UUID(),
        revision: Int = 0,
        storeA: ComparisonStoreSummary,
        storeB: ComparisonStoreSummary,
        matches: [ProductMatch] = [],
        reviews: [ProductMatch] = [],
        rejected: [ProductMatch] = [],
        possiblyMissingInB: [EnjoeiProduct] = [],
        possiblyMissingInA: [EnjoeiProduct] = [],
        unverifiedA: [UnverifiedListing] = [],
        unverifiedB: [UnverifiedListing] = [],
        staleDecisionCount: Int = 0
    ) {
        self.id = id
        self.revision = revision
        self.storeA = storeA
        self.storeB = storeB
        self.matches = matches
        self.reviews = reviews
        self.rejected = rejected
        self.possiblyMissingInB = possiblyMissingInB
        self.possiblyMissingInA = possiblyMissingInA
        self.unverifiedA = unverifiedA
        self.unverifiedB = unverifiedB
        self.staleDecisionCount = staleDecisionCount
    }

    var unverifiedCount: Int { unverifiedA.count + unverifiedB.count }
    var hasProblems: Bool { !storeA.problems.isEmpty || !storeB.problems.isEmpty }

    /// Um anúncio está no resultado como par (forte/confirmado)?
    func isMatched(_ key: ListingKey) -> Bool {
        matches.contains { $0.keyA == key || $0.keyB == key }
    }
}
