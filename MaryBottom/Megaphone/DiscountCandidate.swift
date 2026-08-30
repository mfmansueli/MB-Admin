import Foundation

/// Um produto que pede a decisão de desconto pra alcançar exposição máxima no megafone.
nonisolated struct DiscountCandidate: Identifiable, Equatable, Sendable {
    let product: EnjoeiProduct
    let exposure: MegaphoneExposure
    /// Andamento de aplicar o desconto nesse produto — reaproveita `MegaphoneStatus`, que já cobre
    /// exatamente os estados de uma chamada de megafone (parado/rodando/sucesso/falha).
    var status: MegaphoneStatus = .pending

    var id: Int { product.id }

    var suggestedPriceText: String? {
        guard let price = exposure.priceToIncreaseExposure else { return nil }
        return price.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    /// Percentual de desconto entre o preço original da loja e o preço sugerido, calculado aqui —
    /// não é o `discount` que já vem pronto da API (esse a gente só reaproveita no botão).
    var computedDiscountPercent: Int? {
        guard let original = product.originalPrice, original > 0,
              let suggested = exposure.priceToIncreaseExposure else { return nil }
        return Int(((original - suggested) / original * 100).rounded())
    }
}
