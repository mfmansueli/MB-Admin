import Foundation

/// Um produto na fila do megafone, com o status que a tela mostra.
nonisolated struct MegaphoneItem: Identifiable, Equatable, Sendable, Codable {
    let product: EnjoeiProduct
    var status: MegaphoneStatus = .pending
    /// Como esse produto se encaixa no megafone — `nil` até a exposição ser conferida, ou quando a
    /// conferência não trouxe resposta pra ele.
    var exposure: MegaphoneExposure?

    var id: Int { product.id }

    /// Percentual de desconto entre o preço original da loja e o preço sugerido pelo megafone,
    /// calculado aqui — não é o `discount` que já vem pronto da API (esse só é usado no botão).
    var computedDiscountPercent: Int? {
        guard let original = product.originalPrice, original > 0,
              let suggested = exposure?.priceToIncreaseExposure else { return nil }
        return Int(((original - suggested) / original * 100).rounded())
    }
}
