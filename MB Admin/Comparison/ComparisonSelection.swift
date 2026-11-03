import Foundation

/// O que está marcado na seleção do resultado da comparação: produtos possivelmente ausentes (pra
/// postar na outra loja) e grupos de repetidos (pra apagar os anúncios a mais), com o anúncio que
/// fica em cada grupo quando você trocou o que vem marcado (`DuplicateCleanup.kept`).
nonisolated struct ComparisonSelection: Equatable, Sendable {
    private(set) var productIDs: Set<Int> = []
    private(set) var groupIDs: Set<String> = []
    /// Grupo → o anúncio que você escolheu manter. Fica guardado mesmo desmarcando o grupo, pra
    /// marcar de novo não voltar pro anúncio que vem marcado.
    private(set) var keptByGroup: [String: Int] = [:]

    var isEmpty: Bool { productIDs.isEmpty && groupIDs.isEmpty }
    var count: Int { productIDs.count + groupIDs.count }

    mutating func toggle(productID: Int) {
        if productIDs.remove(productID) == nil { productIDs.insert(productID) }
    }

    mutating func toggle(groupID: String) {
        if groupIDs.remove(groupID) == nil { groupIDs.insert(groupID) }
    }

    mutating func select(groupID: String) {
        groupIDs.insert(groupID)
    }

    /// Escolher o anúncio que fica também marca o grupo.
    mutating func keep(_ productID: Int, inGroup groupID: String) {
        keptByGroup[groupID] = productID
        groupIDs.insert(groupID)
    }

    func isFullySelected(productIDs products: [Int], groupIDs groups: [String]) -> Bool {
        !(products.isEmpty && groups.isEmpty) && products.allSatisfy(productIDs.contains) && groups.allSatisfy(groupIDs.contains)
    }

    /// "todos"/"nenhum": com tudo marcado, desmarca esses; senão, marca todos.
    mutating func toggleAll(productIDs products: [Int], groupIDs groups: [String]) {
        if isFullySelected(productIDs: products, groupIDs: groups) {
            productIDs.subtract(products)
            groupIDs.subtract(groups)
        } else {
            productIDs.formUnion(products)
            groupIDs.formUnion(groups)
        }
    }

    /// Tira o que deixou de estar na tela (outro filtro, revisão manual).
    mutating func keepOnly(productIDs products: Set<Int>, groupIDs groups: Set<String>) {
        productIDs.formIntersection(products)
        groupIDs.formIntersection(groups)
    }

    mutating func removeProducts() { productIDs.removeAll() }
    mutating func removeGroups() { groupIDs.removeAll() }

    mutating func removeAll() {
        productIDs.removeAll()
        groupIDs.removeAll()
        keptByGroup.removeAll()
    }
}
