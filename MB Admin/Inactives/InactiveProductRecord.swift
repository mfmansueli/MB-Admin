import Foundation
import SwiftData

/// Registro SwiftData de um produto inativo — cada campo de `InactiveProduct` vira sua própria
/// coluna (nada de JSON codificado num blob) pra ler um resultado de `FetchDescriptor`/`#Predicate`
/// não precisar de `JSONDecoder` nenhum, só acesso direto às propriedades. `sortIndex` preserva a
/// ordem original da página (a lista não é reordenada ao salvar/reler, só dividida em registros
/// individuais).
///
/// Sem `accountID`: mora num `ModelContainer` próprio da conta (ver `PerAccountModelContainer`), não
/// numa tabela compartilhada entre contas — não tem coluna pra filtrar porque não existe linha de
/// outra conta nesse arquivo pra confundir.
///
/// Valores padrão nas colunas não-opcionais são só pra migração automática de quem já tinha
/// registros salvos num esquema anterior (com `payload`) — todo `init` novo sempre passa os valores
/// de verdade. Ver `SwiftDataInactiveProductsPersistence.wipeStaleSchemaIfNeeded()`: registros do
/// esquema antigo são descartados de propósito (não dá pra reconstruir os campos novos a partir de
/// um `payload` que não existe mais), não deixados com valor padrão errado na tela.
@Model
final class InactiveProductRecord {
    var sortIndex: Int
    var productID: Int = 0
    var path: String = ""
    var title: String = ""
    var price: Double?
    var photoPublicID: String?
    var inactiveSince: String?

    init(sortIndex: Int, product: InactiveProduct) {
        self.sortIndex = sortIndex
        self.productID = product.id
        self.path = product.path
        self.title = product.title
        self.price = product.price
        self.photoPublicID = product.photoPublicID
        self.inactiveSince = product.inactiveSince
    }

    var asInactiveProduct: InactiveProduct {
        InactiveProduct(
            id: productID,
            path: path,
            title: title,
            price: price,
            photoPublicID: photoPublicID,
            inactiveSince: inactiveSince
        )
    }
}
