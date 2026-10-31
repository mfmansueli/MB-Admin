import Foundation

/// Os produtos de "pedem desconto" que o "aplicar nos N" do cabeçalho da seção vai mexer, com os
/// textos do botão e do alerta de confirmação — o uso mais comum da aba, sem passar pela seleção.
///
/// Só os que ainda esperam a decisão, pela mesma regra do botão de aplicar de cada linha
/// (`MegaphoneRowView.isAwaitingDiscount`): na fila (`.pending`), nem apagados nem inativados. Um já
/// megafonado nesta rodada (com ou sem o desconto) continua na seção, mas
/// `MegaphoneRunner.applyDiscount` ignora quem já está `.succeeded` — contar esses prometeria no
/// alerta um desconto que não seria aplicado.
nonisolated struct PendingDiscountBatch: Equatable, Sendable {
    /// Quantos pares "R$ 149 → R$ 127" a mensagem lista antes de resumir o resto em "e mais N" — com
    /// dezenas de produtos pedindo desconto, o alerta inteiro virava uma parede de preços.
    static let maxListedPrices = 10

    let items: [MegaphoneItem]

    /// - Parameter isGone: se o produto já foi apagado ou inativado nesta sessão.
    init(section: [MegaphoneItem], isGone: (Int) -> Bool) {
        items = section.filter {
            $0.needsDiscountDecision && $0.status == .pending && !isGone($0.id)
        }
    }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// "aplicar nos 3" — o resto (o desconto de quê, de quais) o cabeçalho ao lado já diz.
    var buttonLabel: String {
        count == 1 ? "aplicar no 1" : "aplicar nos \(count.formatted())"
    }

    /// Versão do VoiceOver, que lê o botão separado do cabeçalho.
    var accessibilityLabel: String {
        "aplicar o desconto sugerido \(count == 1 ? "no 1" : "nos \(count.formatted())")"
    }

    /// Mesmo título da ação em massa "desconto" da seleção.
    var confirmationTitle: String {
        PublishedBulkAction.applyDiscount.confirmationTitle(count: count)
    }

    /// A mensagem da ação em massa, com o preço de agora e o sugerido de cada um no lugar do ponto
    /// final: "… e é megafonado na hora: R$ 149 → R$ 127, R$ 99 → R$ 69."
    var confirmationMessage: String {
        let base = PublishedBulkAction.applyDiscount.confirmationMessage
        let prices = items.compactMap(Self.priceChange)
        guard !prices.isEmpty else { return base }
        var listed = prices.prefix(Self.maxListedPrices).joined(separator: ", ")
        if prices.count > Self.maxListedPrices {
            listed += " e mais \((prices.count - Self.maxListedPrices).formatted())"
        }
        let sentence = base.hasSuffix(".") ? String(base.dropLast()) : base
        return "\(sentence): \(listed)."
    }

    /// "R$ 149 → R$ 127" — mesmo formato de preço da linha (`EnjoeiProduct.formattedPrice`).
    private static func priceChange(_ item: MegaphoneItem) -> String? {
        guard let current = item.product.formattedPrice,
              let suggested = item.exposure?.priceToIncreaseExposure else { return nil }
        return "\(current) → \(suggested.formatted(.currency(code: "BRL").presentation(.narrow)))"
    }
}
