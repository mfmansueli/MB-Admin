import Foundation
import Testing
@testable import MB_Admin

@Suite("par de produtos da comparação")
struct ProductMatchTests {
    private func match(similarity: Double) -> ProductMatch {
        ProductMatch(
            productA: EnjoeiFixtures.product(id: 1),
            productB: EnjoeiFixtures.product(id: 2),
            similarity: similarity
        )
    }

    @Test("a partir de 80% o par é quase certo; abaixo, vale conferir")
    func quaseCerto() {
        #expect(match(similarity: 0.82).isConfident)
        #expect(match(similarity: 0.8).isConfident)
        #expect(!match(similarity: 0.64).isConfident)
    }

    @Test("o número do anel é o percentual arredondado")
    func percentual() {
        #expect(match(similarity: 0.824).similarityPercent == 82)
        #expect(match(similarity: 0.646).similarityPercent == 65)
        #expect(match(similarity: 1).similarityPercent == 100)
    }
}
