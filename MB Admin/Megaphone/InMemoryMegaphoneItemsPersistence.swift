import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. É o valor
/// padrão de `MegaphoneRunner.init`, pra um runner construído sem pensar em disco (testes,
/// previews) nunca escrever em disco por acidente. A produção passa
/// `SwiftDataMegaphoneItemsPersistence` explicitamente.
@MainActor
final class InMemoryMegaphoneItemsPersistence: MegaphoneItemsPersisting {
    private var items: [MegaphoneItem] = []

    // Default-argument expressions em `MegaphoneRunner.init` são avaliados fora do MainActor —
    // sem isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadItems() -> [MegaphoneItem] {
        items
    }

    func saveItems(_ items: [MegaphoneItem]) {
        self.items = items
    }

    func searchProductIDs(matching query: String, limit: Int) -> [Int] {
        let matched = query.isEmpty ? items : items.filter { $0.product.title.localizedCaseInsensitiveContains(query) }
        return Array(matched.prefix(limit).map(\.id))
    }

    func clearItems() {
        items = []
    }

    func upsertDescription(for product: EnjoeiProduct, description: String) {
        guard let index = items.firstIndex(where: { $0.id == product.id }) else {
            items.append(MegaphoneItem(product: product.withDescription(description)))
            return
        }
        items[index] = MegaphoneItem(
            product: items[index].product.withDescription(description),
            status: items[index].status,
            exposure: items[index].exposure
        )
    }
}
