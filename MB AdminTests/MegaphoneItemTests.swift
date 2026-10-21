import Foundation
import Testing
@testable import MB_Admin

@Suite("cálculo do percentual de desconto do item")
struct MegaphoneItemTests {
    private func makeItem(originalPrice: Double?, suggestedPrice: Double?) -> MegaphoneItem {
        let product = EnjoeiProduct(
            id: 1,
            title: "produto",
            path: "produto-1",
            photoPublicID: nil,
            currentPrice: 100,
            originalPrice: originalPrice
        )
        let exposure = MegaphoneExposure(
            productID: 1,
            kind: .maximumAfterDiscount,
            priceToIncreaseExposure: suggestedPrice,
            discountLabel: "- 99%"
        )
        return MegaphoneItem(product: product, exposure: exposure)
    }

    @Test("calcula o percentual a partir do preço original e do sugerido")
    func calculaPercentual() {
        let item = makeItem(originalPrice: 799, suggestedPrice: 351)
        #expect(item.computedDiscountPercent == 56)
    }

    @Test("sem preço original não calcula nada")
    func semPrecoOriginal() {
        let item = makeItem(originalPrice: nil, suggestedPrice: 351)
        #expect(item.computedDiscountPercent == nil)
    }

    @Test("sem preço sugerido não calcula nada")
    func semPrecoSugerido() {
        let item = makeItem(originalPrice: 799, suggestedPrice: nil)
        #expect(item.computedDiscountPercent == nil)
    }

    @Test("sem exposição nenhuma não calcula nada")
    func semExposicao() {
        let product = EnjoeiProduct(
            id: 1, title: "produto", path: "produto-1", photoPublicID: nil, currentPrice: 100, originalPrice: 799
        )
        let item = MegaphoneItem(product: product)
        #expect(item.computedDiscountPercent == nil)
    }

    @Test("pede decisão de desconto só quando a exposição pede")
    func pedeDecisaoDeDesconto() {
        #expect(makeItem(originalPrice: 200, suggestedPrice: 100).needsDiscountDecision)

        let semExposicao = MegaphoneItem(product: EnjoeiFixtures.product(id: 2))
        #expect(!semExposicao.needsDiscountDecision)

        let deGraca = MegaphoneItem(
            product: EnjoeiFixtures.product(id: 3),
            exposure: MegaphoneExposure(productID: 3, kind: .maximumForFree, priceToIncreaseExposure: nil, discountLabel: nil)
        )
        #expect(!deGraca.needsDiscountDecision)
    }

    // MARK: - desconto já aplicado (original → atual)

    private func product(currentPrice: Double?, originalPrice: Double?) -> MegaphoneItem {
        MegaphoneItem(product: EnjoeiProduct(
            id: 7,
            title: "anel",
            path: "anel-7",
            photoPublicID: nil,
            currentPrice: currentPrice,
            originalPrice: originalPrice
        ))
    }

    @Test("desconto já aplicado vem do original pro atual")
    func descontoJaAplicado() {
        #expect(product(currentPrice: 684, originalPrice: 799).appliedDiscountPercent == 14)
        #expect(product(currentPrice: 399, originalPrice: 798).appliedDiscountPercent == 50)
    }

    @Test("sem desconto (atual igual ou acima do original) não mostra percentual")
    func semDescontoAplicado() {
        #expect(product(currentPrice: 799, originalPrice: 799).appliedDiscountPercent == nil)
        #expect(product(currentPrice: 900, originalPrice: 799).appliedDiscountPercent == nil)
        #expect(product(currentPrice: 100, originalPrice: nil).appliedDiscountPercent == nil)
    }

    @Test("desconto que arredonda pra 0% não aparece")
    func descontoQueArredondaPraZero() {
        #expect(product(currentPrice: 998, originalPrice: 1000).appliedDiscountPercent == nil)
    }
}
