import Foundation

/// Um produto na fila do megafone, com o status que a tela mostra.
nonisolated struct MegaphoneItem: Identifiable, Equatable, Sendable {
    let product: EnjoeiProduct
    var status: MegaphoneStatus = .pending
    /// Como esse produto se encaixa no megafone — `nil` até a exposição ser conferida, ou quando a
    /// conferência não trouxe resposta pra ele.
    var exposure: MegaphoneExposure? = nil

    var id: Int { product.id }
}
