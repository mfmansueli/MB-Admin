import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. Valor padrão de
/// `SmartPriceProductsLoader.init`, mesmo raciocínio de `InMemoryInactiveProductsPersistence`: um
/// loader construído sem pensar em disco (testes, previews) nunca escreve em disco por acidente. A
/// produção passa `SwiftDataSmartPriceProductsPersistence` explicitamente.
@MainActor
final class InMemorySmartPriceProductsPersistence: SmartPriceProductsPersisting {
    private var itemsByAccountID: [EnjoeiAccountID: [SmartPriceProduct]] = [:]

    // Default-argument expressions em `SmartPriceProductsLoader.init` são avaliados fora do
    // MainActor — sem isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadItems(accountID: EnjoeiAccountID) -> [SmartPriceProduct] {
        itemsByAccountID[accountID] ?? []
    }

    func saveItems(_ items: [SmartPriceProduct], accountID: EnjoeiAccountID) {
        itemsByAccountID[accountID] = items
    }

    func clearItems(accountID: EnjoeiAccountID) {
        itemsByAccountID[accountID] = nil
    }
}
