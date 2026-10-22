import Foundation
import Testing
@testable import MB_Admin

@Suite("aplicar nos N de pedem desconto")
struct PendingDiscountBatchTests {
    /// `suggestedPrice` nil = produto que não pede desconto.
    private func item(
        id: Int,
        price: Double = 100,
        suggestedPrice: Double? = 80,
        status: MegaphoneStatus = .pending
    ) -> MegaphoneItem {
        let product = EnjoeiProduct(
            id: id,
            title: "produto \(id)",
            path: "produto-\(id)",
            photoPublicID: nil,
            currentPrice: price,
            originalPrice: price
        )
        let exposure = suggestedPrice.map {
            MegaphoneExposure(productID: id, kind: .maximumAfterDiscount, priceToIncreaseExposure: $0, discountLabel: nil)
        }
        return MegaphoneItem(product: product, status: status, exposure: exposure)
    }

    private func brl(_ value: Double) -> String {
        value.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    @Test("conta só os que ainda esperam a decisão, na ordem da seção")
    func contaSoOsQueEsperam() {
        let section = [
            item(id: 1),
            item(id: 2, status: .succeeded),
            item(id: 3, status: .megaphoning),
            item(id: 4),
            item(id: 5, status: .failed("504"))
        ]

        let batch = PendingDiscountBatch(section: section) { _ in false }

        #expect(batch.items.map(\.id) == [1, 4])
        #expect(batch.count == 2)
    }

    @Test("apagados e inativados ficam de fora")
    func ignoraQuemJaSaiu() {
        let batch = PendingDiscountBatch(section: [item(id: 1), item(id: 2), item(id: 3)]) { $0 == 2 }

        #expect(batch.items.map(\.id) == [1, 3])
    }

    @Test("produto sem desconto sugerido não entra")
    func ignoraQuemNaoPedeDesconto() {
        let batch = PendingDiscountBatch(section: [item(id: 1, suggestedPrice: nil), item(id: 2)]) { _ in false }

        #expect(batch.items.map(\.id) == [2])
    }

    @Test("nenhum esperando: lote vazio, sem botão")
    func loteVazio() {
        let batch = PendingDiscountBatch(section: [item(id: 1, status: .succeeded)]) { _ in false }

        #expect(batch.isEmpty)
    }

    @Test("rótulo do botão no plural e no singular")
    func rotuloDoBotao() {
        let three = PendingDiscountBatch(section: [item(id: 1), item(id: 2), item(id: 3)]) { _ in false }
        let one = PendingDiscountBatch(section: [item(id: 1)]) { _ in false }

        #expect(three.buttonLabel == "aplicar nos 3")
        #expect(one.buttonLabel == "aplicar no 1")
        #expect(three.accessibilityLabel == "aplicar o desconto sugerido nos 3")
    }

    @Test("mesmo título da ação em massa de desconto")
    func tituloDaConfirmacao() {
        let batch = PendingDiscountBatch(section: [item(id: 1), item(id: 2), item(id: 3)]) { _ in false }

        #expect(batch.confirmationTitle == "aplicar desconto e megafonar 3 produtos?")
        #expect(batch.confirmationTitle == PublishedBulkAction.applyDiscount.confirmationTitle(count: 3))
    }

    @Test("mensagem da ação em massa com o preço de agora e o sugerido de cada um")
    func mensagemComPrecos() {
        let section = [
            item(id: 1, price: 149, suggestedPrice: 127),
            item(id: 2, price: 99, suggestedPrice: 69),
            item(id: 3, price: 299, suggestedPrice: 132)
        ]

        let batch = PendingDiscountBatch(section: section) { _ in false }

        #expect(
            batch.confirmationMessage
                == "cada produto vai pro preço com desconto sugerido pelo megafone, e é megafonado na hora: "
                + "\(brl(149)) → \(brl(127)), \(brl(99)) → \(brl(69)), \(brl(299)) → \(brl(132))."
        )
    }

    @Test("muitos produtos: lista os primeiros e resume o resto")
    func mensagemResumeOResto() {
        let section = (1...13).map { item(id: $0, price: 100, suggestedPrice: 80) }

        let batch = PendingDiscountBatch(section: section) { _ in false }

        let pair = "\(brl(100)) → \(brl(80))"
        let listed = Array(repeating: pair, count: PendingDiscountBatch.maxListedPrices).joined(separator: ", ")
        #expect(batch.confirmationMessage.hasSuffix(": \(listed) e mais 3."))
    }
}
