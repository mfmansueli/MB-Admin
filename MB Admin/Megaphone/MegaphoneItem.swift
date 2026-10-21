import Foundation

/// Um produto na fila do megafone, com o status que a tela mostra.
nonisolated struct MegaphoneItem: Identifiable, Equatable, Sendable, Codable {
    let product: EnjoeiProduct
    var status: MegaphoneStatus = .pending
    /// Como esse produto se encaixa no megafone — `nil` até a exposição ser conferida, ou quando a
    /// conferência não trouxe resposta pra ele.
    var exposure: MegaphoneExposure?

    var id: Int { product.id }

    /// Entra na seção "pedem desconto" (e na contagem "N pedem desconto" da lista de contas) — só
    /// pela classificação da exposição, independente do status da rodada: a rodada megafona esses
    /// produtos também (sem desconto), e eles continuam pedindo a decisão depois disso.
    var needsDiscountDecision: Bool {
        exposure?.kind.requiresDiscountDecision == true
    }

    /// Desconto que o anúncio já tem hoje: do preço original da loja pro preço atual (o riscado e o
    /// em destaque na linha). `nil` sem desconto nenhum — ou um tão pequeno que arredonda pra 0%.
    var appliedDiscountPercent: Int? {
        guard let original = product.originalPrice, original > 0,
              let current = product.currentPrice, current < original else { return nil }
        let percent = Int(((original - current) / original * 100).rounded())
        return percent > 0 ? percent : nil
    }

    /// Percentual de desconto entre o preço original da loja e o preço sugerido pelo megafone,
    /// calculado aqui — não é o `discount` que já vem pronto da API (esse só é usado no botão).
    var computedDiscountPercent: Int? {
        guard let original = product.originalPrice, original > 0,
              let suggested = exposure?.priceToIncreaseExposure else { return nil }
        return Int(((original - suggested) / original * 100).rounded())
    }
}
