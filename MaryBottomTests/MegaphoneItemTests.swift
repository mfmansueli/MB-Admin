import Foundation
import Testing
@testable import MaryBottom

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
}
