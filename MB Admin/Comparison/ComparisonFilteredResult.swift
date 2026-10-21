import Foundation

/// O que sobra do resultado da comparação depois do filtro e da busca — montado de uma vez por
/// `ComparisonResultView.recomputeFilteredItems()` (em vez de refiltrar a cada leitura no `body`),
/// só quando o filtro ou a busca mudam de verdade.
nonisolated struct ComparisonFilteredResult: Sendable {
    private(set) var matches: [ProductMatch] = []
    private(set) var onlyInA: [EnjoeiProduct] = []
    private(set) var onlyInB: [EnjoeiProduct] = []

    init() {}

    /// A busca olha o título dos dois lados de um par — achar pelo nome que está na outra conta
    /// também vale.
    init(result: AccountComparisonResult, filter: ComparisonResultFilter, searchText: String) {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        func matchesSearch(_ title: String) -> Bool {
            text.isEmpty || title.localizedCaseInsensitiveContains(text)
        }
        if filter.includes(.matches) {
            matches = result.matches.filter { matchesSearch($0.productA.title) || matchesSearch($0.productB.title) }
        }
        if filter.includes(.onlyInA) {
            onlyInA = result.onlyInA.filter { matchesSearch($0.title) }
        }
        if filter.includes(.onlyInB) {
            onlyInB = result.onlyInB.filter { matchesSearch($0.title) }
        }
    }

    var isEmpty: Bool { matches.isEmpty && onlyInA.isEmpty && onlyInB.isEmpty }

    /// Os pares ("em comum") nunca entram na seleção — não tem o que postar de um produto que já
    /// existe nas duas contas.
    var selectableIDs: [Int] { onlyInA.map(\.id) + onlyInB.map(\.id) }
}
