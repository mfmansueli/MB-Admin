import Foundation
import Testing
@testable import MaryBottom

@Suite("cálculo do percentual de desconto")
struct DiscountCandidateTests {
    private func makeCandidate(originalPrice: Double?, suggestedPrice: Double?) -> DiscountCandidate {
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
        return DiscountCandidate(product: product, exposure: exposure)
    }

    @Test("calcula o percentual a partir do preço original e do sugerido")
    func calculaPercentual() {
        let candidate = makeCandidate(originalPrice: 799, suggestedPrice: 351)
        #expect(candidate.computedDiscountPercent == 56)
    }

    @Test("sem preço original não calcula nada")
    func semPrecoOriginal() {
        let candidate = makeCandidate(originalPrice: nil, suggestedPrice: 351)
        #expect(candidate.computedDiscountPercent == nil)
    }

    @Test("sem preço sugerido não calcula nada")
    func semPrecoSugerido() {
        let candidate = makeCandidate(originalPrice: 799, suggestedPrice: nil)
        #expect(candidate.computedDiscountPercent == nil)
    }
}
