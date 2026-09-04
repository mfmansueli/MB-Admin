import Foundation
import SwiftData

/// Registro SwiftData de um produto inativo — cada campo de `InactiveProduct` vira sua própria
/// coluna (nada de JSON codificado num blob) pra ler um resultado de `FetchDescriptor`/`#Predicate`
/// não precisar de `JSONDecoder` nenhum, só acesso direto às propriedades. `sortIndex` preserva a
/// ordem original da página (a lista não é reordenada ao salvar/reler, só dividida em registros
/// individuais).
///
/// Valores padrão nas colunas não-opcionais são só pra migração automática de quem já tinha
/// registros salvos num esquema anterior (com `payload`) — todo `init` novo sempre passa os valores
/// de verdade. Ver `SwiftDataInactiveProductsPersistence.wipeStaleSchemaIfNeeded()`: registros do
/// esquema antigo são descartados de propósito (não dá pra reconstruir os campos novos a partir de
/// um `payload` que não existe mais), não deixados com valor padrão errado na tela.
@Model
final class InactiveProductRecord {
    // Índice composto (não dois separados) — `accountID` sozinho já usa o prefixo esquerdo dele
    // pra consultas que não filtram por título (`loadItems`/`clearItems`), e a busca por título usa
    // o índice inteiro pra pular direto pras linhas da conta certa antes de escanear por
    // `#Predicate` (não dá pra indexar "contém em qualquer parte" — só a parte de `accountID`).
    // Sem isso, com várias contas de 1500+ itens compartilhando a mesma tabela, toda busca varria
    // as linhas de todas as contas juntas antes de filtrar pela conta certa.
    @available(iOS 18, macOS 15, *)
    #Index<InactiveProductRecord>([\.accountID, \.title])

    var accountID: EnjoeiAccountID
    var sortIndex: Int
    var productID: Int = 0
    var path: String = ""
    var title: String = ""
    var price: Double?
    var photoPublicID: String?
    var inactiveSince: String?

    init(accountID: EnjoeiAccountID, sortIndex: Int, product: InactiveProduct) {
        self.accountID = accountID
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
