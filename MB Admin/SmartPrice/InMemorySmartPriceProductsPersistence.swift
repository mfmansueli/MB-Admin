import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. Valor padrão de
/// `SmartPriceProductsLoader.init`, mesmo raciocínio de `InMemoryInactiveProductsPersistence`: um
/// loader construído sem pensar em disco (testes, previews) nunca escreve em disco por acidente. A
/// produção passa `SwiftDataSmartPriceProductsPersistence` explicitamente.
@MainActor
final class InMemorySmartPriceProductsPersistence: SmartPriceProductsPersisting {
    private var items: [SmartPriceProduct] = []
    private var titlesByID: [Int: String] = [:]

    // Default-argument expressions em `SmartPriceProductsLoader.init` são avaliados fora do
    // MainActor — sem isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadItems() -> [SmartPriceProduct] {
        items
    }

    func saveItems(_ items: [SmartPriceProduct]) {
        self.items = items
    }

    func appendPage(_ items: [SmartPriceProduct], startingAt offset: Int, titleResolver: (Int) -> String?) {
        self.items.append(contentsOf: items)
        for item in items {
            titlesByID[item.id] = titleResolver(item.id) ?? ""
        }
    }

    func backfillTitles(resolver: (Int) -> String?) {
        for item in items {
            guard let resolved = resolver(item.id) else { continue }
            titlesByID[item.id] = resolved
        }
    }

    func search(matching query: String, limit: Int) -> [SmartPriceProduct] {
        let matched = query.isEmpty
            ? items
            : items.filter { (titlesByID[$0.id] ?? "").localizedCaseInsensitiveContains(query) }
        return Array(matched.prefix(limit))
    }

    func clearItems() {
        items = []
        titlesByID = [:]
    }
}
