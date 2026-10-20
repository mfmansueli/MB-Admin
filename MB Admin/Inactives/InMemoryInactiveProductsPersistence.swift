import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. Valor padrão de
/// `InactiveProductsLoader.init`, mesmo raciocínio de `InMemoryMegaphoneItemsPersistence`: um
/// loader construído sem pensar em disco (testes, previews) nunca escreve em disco por acidente. A
/// produção passa `SwiftDataInactiveProductsPersistence` explicitamente.
@MainActor
final class InMemoryInactiveProductsPersistence: InactiveProductsPersisting {
    private var items: [InactiveProduct] = []

    // Default-argument expressions em `InactiveProductsLoader.init` são avaliados fora do
    // MainActor — sem isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadItems() -> [InactiveProduct] {
        items
    }

    func saveItems(_ items: [InactiveProduct]) {
        self.items = items
    }

    func appendPage(_ items: [InactiveProduct], startingAt offset: Int) {
        self.items.append(contentsOf: items)
    }

    func search(matching query: String, limit: Int) -> [InactiveProduct] {
        let matched = query.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return Array(matched.prefix(limit))
    }

    func clearItems() {
        items = []
    }
}
