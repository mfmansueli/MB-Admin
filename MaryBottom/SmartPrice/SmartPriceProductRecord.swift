import Foundation
import SwiftData

/// Registro SwiftData de um produto sem preço esperto — cada campo de `SmartPriceProduct` vira sua
/// própria coluna (nada de JSON codificado num blob), mesmo raciocínio de `InactiveProductRecord`.
/// Sem `accountID` pelo mesmo motivo: mora num `ModelContainer` próprio da conta (ver
/// `PerAccountModelContainer`), não numa tabela compartilhada entre contas.
///
/// `title` é a exceção: **não** é um campo nativo de `SmartPriceProduct` (a API de preço esperto só
/// devolve id e preço) — quem resolve o nome é sempre uma fonte externa (a aba "publicados"), então
/// pode ficar vazio até essa fonte responder (ver `SmartPriceProductsLoader.titleResolver`/
/// `backfillTitles`).
///
/// Valores padrão nas colunas não-opcionais são só pra migração automática de quem já tinha
/// registros salvos num esquema anterior (com `payload`) — todo `init` novo sempre passa os valores
/// de verdade. Ver `SwiftDataSmartPriceProductsPersistence.wipeStaleSchemaIfNeeded()`.
@Model
final class SmartPriceProductRecord {
    var sortIndex: Int
    var productID: Int = 0
    var title: String = ""
    var price: Double = 0
    var minPrice: Double = 0
    var maxPrice: Double = 0
    var blocked: Bool = false
    var smartPriceEnabled: Bool = false
    var statusText: String?
    var statusColor: String?
    var photoPublicID: String?

    init(sortIndex: Int, title: String, product: SmartPriceProduct) {
        self.sortIndex = sortIndex
        self.productID = product.id
        self.title = title
        self.price = product.price
        self.minPrice = product.minPrice
        self.maxPrice = product.maxPrice
        self.blocked = product.blocked
        self.smartPriceEnabled = product.smartPriceEnabled
        self.statusText = product.statusText
        self.statusColor = product.statusColor
        self.photoPublicID = product.photoPublicID
    }

    var asSmartPriceProduct: SmartPriceProduct {
        SmartPriceProduct(
            id: productID,
            price: price,
            minPrice: minPrice,
            maxPrice: maxPrice,
            blocked: blocked,
            smartPriceEnabled: smartPriceEnabled,
            statusText: statusText,
            statusColor: statusColor,
            photoPublicID: photoPublicID
        )
    }
}
