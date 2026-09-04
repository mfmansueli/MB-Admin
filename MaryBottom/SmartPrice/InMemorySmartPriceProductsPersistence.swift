import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. Valor padrão de
/// `SmartPriceProductsLoader.init`, mesmo raciocínio de `InMemoryInactiveProductsPersistence`: um
/// loader construído sem pensar em disco (testes, previews) nunca escreve em disco por acidente. A
/// produção passa `SwiftDataSmartPriceProductsPersistence` explicitamente.
@MainActor
final class InMemorySmartPriceProductsPersistence: SmartPriceProductsPersisting {
    private var itemsByAccountID: [EnjoeiAccountID: [SmartPriceProduct]] = [:]
    private var titlesByAccountID: [EnjoeiAccountID: [Int: String]] = [:]

    // Default-argument expressions em `SmartPriceProductsLoader.init` são avaliados fora do
    // MainActor — sem isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadItems(accountID: EnjoeiAccountID) -> [SmartPriceProduct] {
        itemsByAccountID[accountID] ?? []
    }

    func saveItems(_ items: [SmartPriceProduct], accountID: EnjoeiAccountID) {
        itemsByAccountID[accountID] = items
    }

    func appendPage(
        _ items: [SmartPriceProduct],
        startingAt offset: Int,
        accountID: EnjoeiAccountID,
        titleResolver: (Int) -> String?
    ) {
        itemsByAccountID[accountID, default: []].append(contentsOf: items)
        for item in items {
            titlesByAccountID[accountID, default: [:]][item.id] = titleResolver(item.id) ?? ""
        }
    }

    func backfillTitles(resolver: (Int) -> String?, accountID: EnjoeiAccountID) {
        for item in itemsByAccountID[accountID] ?? [] {
            guard let resolved = resolver(item.id) else { continue }
            titlesByAccountID[accountID, default: [:]][item.id] = resolved
        }
    }

    func search(matching query: String, accountID: EnjoeiAccountID, limit: Int) -> [SmartPriceProduct] {
        let items = itemsByAccountID[accountID] ?? []
        let titles = titlesByAccountID[accountID] ?? [:]
        let matched = query.isEmpty
            ? items
            : items.filter { (titles[$0.id] ?? "").localizedCaseInsensitiveContains(query) }
        return Array(matched.prefix(limit))
    }

    func clearItems(accountID: EnjoeiAccountID) {
        itemsByAccountID[accountID] = nil
        titlesByAccountID[accountID] = nil
    }
}
