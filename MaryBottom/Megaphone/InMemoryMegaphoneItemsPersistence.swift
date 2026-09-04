import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. É o valor
/// padrão de `MegaphoneRunner.init`, pra um runner construído sem pensar em disco (testes,
/// previews) nunca escrever em disco por acidente. A produção passa
/// `SwiftDataMegaphoneItemsPersistence` explicitamente.
@MainActor
final class InMemoryMegaphoneItemsPersistence: MegaphoneItemsPersisting {
    private var itemsByAccountID: [EnjoeiAccountID: [MegaphoneItem]] = [:]

    // Default-argument expressions em `MegaphoneRunner.init` são avaliados fora do MainActor —
    // sem isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadItems(accountID: EnjoeiAccountID) -> [MegaphoneItem] {
        itemsByAccountID[accountID] ?? []
    }

    func saveItems(_ items: [MegaphoneItem], accountID: EnjoeiAccountID) {
        itemsByAccountID[accountID] = items
    }

    func searchProductIDs(matching query: String, accountID: EnjoeiAccountID, limit: Int) -> [Int] {
        let items = itemsByAccountID[accountID] ?? []
        let matched = query.isEmpty ? items : items.filter { $0.product.title.localizedCaseInsensitiveContains(query) }
        return Array(matched.prefix(limit).map(\.id))
    }

    func clearItems(accountID: EnjoeiAccountID) {
        itemsByAccountID[accountID] = nil
    }
}
