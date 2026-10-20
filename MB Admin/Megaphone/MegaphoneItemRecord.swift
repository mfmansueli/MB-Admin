import Foundation
import SwiftData

/// Registro SwiftData de um produto carregado pelo megafone — cada campo de `EnjoeiProduct` vira
/// sua própria coluna (nada de JSON codificado num blob), mesmo raciocínio de
/// `InactiveProductRecord`/`SmartPriceProductRecord`. `sortIndex` preserva a ordem original da
/// vitrine. Sem `accountID` pelo mesmo motivo dos outros dois: mora num `ModelContainer` próprio da
/// conta (ver `PerAccountModelContainer`).
///
/// `status`/`exposure` do `MegaphoneItem` original **não** viram colunas — `status` é sempre
/// `.pending` no momento em que `MegaphoneRunner.setLoadedItems` persiste (a lista é gravada logo
/// depois de carregar a loja, antes de qualquer produto ser megafonado; nenhuma megafonagem em
/// andamento chega a ser persistida, só existe ao vivo em `MegaphoneRunner.items`), então reconstruir
/// sempre como `.pending` em `asMegaphoneItem` já é fiel ao que sempre foi salvo. `exposure` fica
/// como um blob pequeno à parte (`exposurePayload`) — só é lido de volta em `loadItems()` (o
/// carregamento inicial, uma vez só, nunca no caminho de busca), então o custo de decodificar não
/// se repete por resultado de busca.
///
/// Valores padrão nas colunas não-opcionais são só pra migração automática de quem já tinha
/// registros salvos num esquema anterior (com `payload`) — todo `init` novo sempre passa os valores
/// de verdade. Ver `SwiftDataMegaphoneItemsPersistence.wipeStaleSchemaIfNeeded()`.
@Model
final class MegaphoneItemRecord {
    var sortIndex: Int
    var productID: Int = 0
    var title: String = ""
    var path: String = ""
    var photoPublicID: String?
    var currentPrice: Double?
    var originalPrice: Double?
    var exposurePayload: Data?
    /// Preenchido por `ProductDetailsLoader`, bem depois do carregamento inicial — `nil` até
    /// alguém tocar o botão de buscar detalhes completos.
    var descriptionText: String?

    init(sortIndex: Int, item: MegaphoneItem) {
        self.sortIndex = sortIndex
        self.productID = item.product.id
        self.title = item.product.title
        self.path = item.product.path
        self.photoPublicID = item.product.photoPublicID
        self.currentPrice = item.product.currentPrice
        self.originalPrice = item.product.originalPrice
        self.descriptionText = item.product.description
        if let exposure = item.exposure {
            self.exposurePayload = try? JSONEncoder().encode(exposure)
        }
    }

    var asMegaphoneItem: MegaphoneItem {
        var product = EnjoeiProduct(
            id: productID,
            title: title,
            path: path,
            photoPublicID: photoPublicID,
            currentPrice: currentPrice,
            originalPrice: originalPrice
        )
        if let descriptionText {
            product = product.withDescription(descriptionText)
        }
        let exposure = exposurePayload.flatMap { try? JSONDecoder().decode(MegaphoneExposure.self, from: $0) }
        return MegaphoneItem(product: product, status: .pending, exposure: exposure)
    }
}
