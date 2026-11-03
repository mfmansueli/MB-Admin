import Foundation
import Testing
@testable import MB_Admin

@Suite("diferença detalhada entre os dois lados de um par")
struct ProductMatchDifferenceTests {
    private func pair(_ productA: EnjoeiProduct, _ productB: EnjoeiProduct) -> ProductMatch {
        ComparisonFixtures.match(productA, productB, status: .needsReview)
    }

    @Test("títulos idênticos, sem descrição: nenhuma palavra diferente")
    func titulosIdenticosSemDiferenca() {
        let productA = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925")
        let productB = EnjoeiFixtures.product(id: 2, title: "colar curto prata 925")

        let difference = ProductMatchDifference(match: pair(productA, productB))

        #expect(difference.onlyInA.isEmpty)
        #expect(difference.onlyInB.isEmpty)
    }

    @Test("aponta exatamente a palavra que só existe de um lado")
    func apontaPalavraQueSoExisteDeUmLado() {
        let productA = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925 zircônia branca")
        let productB = EnjoeiFixtures.product(id: 2, title: "colar curto prata 925 zircônia")

        let difference = ProductMatchDifference(match: pair(productA, productB))

        #expect(difference.onlyInA == ["branca"])
        #expect(difference.onlyInB.isEmpty)
    }

    /// Mesmo caso relatado pelo usuário: só o peso muda entre as duas descrições ("2.6 gramas" vs.
    /// "1 grama") — o ponto decimal vira separador de token, então "2.6" solta dois tokens ("2" e
    /// "6") que só existem do lado com o peso quebrado.
    @Test("descrições quase idênticas: número decimal aparece separado em dois tokens")
    func descricoesQuaseIdenticasNumeroDecimalSeparaEmDoisTokens() {
        let title = "brinco oval zircônia lavanda cravejado - prata 925"
        let commonDescription = "brinco oval zircônia lavanda cravejado com zircônia crystal - prata 925\ncódigo: x379249"
        let descriptionA = commonDescription + "\npeso: 2.6 gramas o par\nmedidas: 1.0 cm x 0.9 mm"
        let descriptionB = commonDescription + "\npeso: 1 grama o par\nmedidas: 1.0 cm x 0.9 mm"
        let productA = EnjoeiFixtures.product(id: 1, title: title).withDescription(descriptionA)
        let productB = EnjoeiFixtures.product(id: 2, title: title).withDescription(descriptionB)

        let difference = ProductMatchDifference(match: pair(productA, productB))

        #expect(difference.onlyInA == ["2", "6"])
        #expect(difference.onlyInB.isEmpty)
    }
}
