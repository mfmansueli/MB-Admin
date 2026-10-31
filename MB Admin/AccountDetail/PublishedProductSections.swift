import Foundation

/// As duas seções da aba "publicados": primeiro o que pede decisão de desconto, depois todo o
/// resto (do maior desconto já aplicado pro menor) — cada produto em uma seção só. Montado de uma vez por
/// `AccountPublishedTabView.recomputeSections()` (em vez de refiltrar a cada leitura), só quando a
/// lista, o filtro ou a busca mudam de verdade.
nonisolated struct PublishedProductSections: Sendable {
    enum Kind: Hashable, Sendable {
        case discount
        case others
    }

    private(set) var discount: [MegaphoneItem] = []
    private(set) var others: [MegaphoneItem] = []

    init() {}

    /// - Parameter matchingIDs: ids que batem com a busca — `nil` sem busca nenhuma (mostra tudo).
    init(items: [MegaphoneItem], filter: AccountProductFilter, matchingIDs: Set<Int>?) {
        let visible = matchingIDs.map { ids in items.filter { ids.contains($0.id) } } ?? items
        // Crescente pelo desconto que o megafone está sugerindo — quem precisa de um corte menor
        // pra alcançar exposição máxima aparece primeiro.
        discount = visible
            .filter(\.needsDiscountDecision)
            .sorted { ($0.computedDiscountPercent ?? 0) < ($1.computedDiscountPercent ?? 0) }
        others = filter == .discountOnly ? [] : Self.byAppliedDiscountDescending(visible.filter { !$0.needsDiscountDecision })
    }

    /// Decrescente pelo desconto que o anúncio já tem hoje (riscado → atual, o mesmo "-N%" da
    /// linha) — os mais descontados no topo, os sem desconto no fim. Empate (inclusive entre todos
    /// os sem desconto) fica na ordem em que a loja devolveu, desempatado explicitamente pelo
    /// índice pra não depender da estabilidade do `sorted`. O percentual é calculado uma vez por
    /// item, não a cada comparação: isso roda a cada lote de produtos megafonados, em catálogos de
    /// 1500+.
    private static func byAppliedDiscountDescending(_ items: [MegaphoneItem]) -> [MegaphoneItem] {
        let keyed: [(index: Int, percent: Int, item: MegaphoneItem)] = items.enumerated().map { index, item in
            (index, item.appliedDiscountPercent ?? 0, item)
        }
        return keyed
            .sorted { lhs, rhs in lhs.percent != rhs.percent ? lhs.percent > rhs.percent : lhs.index < rhs.index }
            .map(\.item)
    }

    var isEmpty: Bool { discount.isEmpty && others.isEmpty }

    func items(in kind: Kind) -> [MegaphoneItem] {
        switch kind {
        case .discount: discount
        case .others: others
        }
    }

    /// "Selecionar todos"/"desmarcar todos" de um grupo de ids (a tela inteira, ou só uma seção):
    /// com todos já marcados, desmarca só esses — o resto da seleção fica como estava; senão, marca
    /// os que faltam.
    static func togglingAll(_ ids: [Int], in selection: Set<Int>) -> Set<Int> {
        guard !ids.isEmpty else { return selection }
        if ids.allSatisfy(selection.contains) {
            return selection.subtracting(ids)
        }
        return selection.union(ids)
    }

    /// Ids das seções abertas, na ordem da tela — "selecionar tudo" só marca o que está à vista,
    /// nunca um produto escondido numa seção recolhida (apagar em massa algo que nem apareceu na
    /// tela seria fácil demais).
    func visibleIDs(collapsed: Set<Kind>) -> [Int] {
        [Kind.discount, .others]
            .filter { !collapsed.contains($0) }
            .flatMap { items(in: $0).map(\.id) }
    }
}
