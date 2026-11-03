import Foundation

/// Escolher qual anúncio de um grupo de repetidos fica na loja e quais vão pra fila de ações pra
/// serem apagados. As regras que impedem apagar o produto inteiro:
///
/// - Só grupo **certo** (repetido sem dúvida, ou confirmado por você). "Talvez repetidos" pede
///   "são repetidos" antes — pode ser outra versão.
/// - O anúncio que fica tem que estar na loja (`DuplicateListingState.listed`): nunca um que já está
///   na fila, apagando, apagado ou com a exclusão falhada (ela ainda pode ser tentada de novo).
/// - Só os outros anúncios **na loja** vão pra fila — quem já está nela não entra duas vezes.
/// - Grupo com menos de dois anúncios ainda na loja não tem o que apagar.
///
/// Sem escolha, fica o mais antigo (o número de anúncio menor): costuma ser o que tem mais tempo de
/// loja, curtidas e visitas.
nonisolated enum DuplicateCleanup {
    static func isSelectable(_ group: StoreDuplicateGroup, states: [Int: DuplicateListingState]) -> Bool {
        group.isCertain && listed(group, states: states).count >= 2
    }

    /// O anúncio que fica: a escolha, se ainda está na loja; senão, o mais antigo que está.
    static func kept(_ group: StoreDuplicateGroup, choice: Int?, states: [Int: DuplicateListingState]) -> Int? {
        let listed = listed(group, states: states)
        if let choice, listed.contains(where: { $0.id == choice }) { return choice }
        return listed.map(\.id).min()
    }

    /// Os anúncios que vão pra fila pra serem apagados — vazio quando não sobraria nenhum na loja.
    static func deletions(_ group: StoreDuplicateGroup, choice: Int?, states: [Int: DuplicateListingState]) -> [EnjoeiProduct] {
        guard isSelectable(group, states: states), let kept = kept(group, choice: choice, states: states) else { return [] }
        return listed(group, states: states).filter { $0.id != kept }
    }

    private static func listed(_ group: StoreDuplicateGroup, states: [Int: DuplicateListingState]) -> [EnjoeiProduct] {
        group.products.filter { (states[$0.id] ?? .listed).isListed }
    }
}
