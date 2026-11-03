import Foundation

/// O que sobra do resultado da comparação depois do filtro e da busca — montado de uma vez por
/// `ComparisonResultView.recomputeFilteredItems()` (em vez de refiltrar a cada leitura no `body`),
/// só quando o filtro, a busca ou o resultado (uma revisão manual) mudam de verdade.
nonisolated struct ComparisonFilteredResult: Sendable {
    private(set) var matches: [ProductMatch] = []
    private(set) var reviews: [ProductMatch] = []
    private(set) var families: [ProductFamily] = []
    /// Produtos de A sem indício em B.
    private(set) var missingInB: [EnjoeiProduct] = []
    /// Produtos de B sem indício em A.
    private(set) var missingInA: [EnjoeiProduct] = []
    private(set) var unverifiedA: [UnverifiedListing] = []
    private(set) var unverifiedB: [UnverifiedListing] = []
    private(set) var rejected: [ProductMatch] = []

    init() {}

    /// A busca olha o título dos dois lados de um par — achar pelo nome que está na outra conta
    /// também vale.
    init(result: AccountComparisonResult, filter: ComparisonResultFilter, searchText: String) {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        func matchesSearch(_ title: String) -> Bool {
            text.isEmpty || title.localizedCaseInsensitiveContains(text)
        }
        func pairMatches(_ match: ProductMatch) -> Bool {
            matchesSearch(match.productA.title) || matchesSearch(match.productB.title)
        }
        if filter.includes(.matches) { matches = result.matches.filter(pairMatches) }
        if filter.includes(.review) { reviews = result.reviews.filter(pairMatches) }
        if filter.includes(.variants) { families = result.families.filter { text.isEmpty || $0.matchesSearch(text) } }
        if filter.includes(.missingInB) { missingInB = result.possiblyMissingInB.filter { matchesSearch($0.title) } }
        if filter.includes(.missingInA) { missingInA = result.possiblyMissingInA.filter { matchesSearch($0.title) } }
        if filter.includes(.unverified) {
            unverifiedA = result.unverifiedA.filter { matchesSearch($0.product.title) }
            unverifiedB = result.unverifiedB.filter { matchesSearch($0.product.title) }
        }
        if filter.includes(.rejected) { rejected = result.rejected.filter(pairMatches) }
    }

    var isEmpty: Bool {
        matches.isEmpty && reviews.isEmpty && families.isEmpty && missingInB.isEmpty && missingInA.isEmpty
            && unverifiedA.isEmpty && unverifiedB.isEmpty && rejected.isEmpty
    }

    /// Só os "possivelmente ausentes" entram na seleção — postar na outra loja presume que o
    /// produto não está lá, e só eles têm essa conclusão. Par, revisão e não verificado nunca.
    var selectableIDs: [Int] { missingInB.map(\.id) + missingInA.map(\.id) }
}
