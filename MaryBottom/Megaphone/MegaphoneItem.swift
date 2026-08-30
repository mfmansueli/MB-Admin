import Foundation

/// Um produto na fila do megafone, com o status que a tela mostra.
nonisolated struct MegaphoneItem: Identifiable, Equatable, Sendable {
    let product: EnjoeiProduct
    var status: MegaphoneStatus = .pending

    var id: Int { product.id }
}
