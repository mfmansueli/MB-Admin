import Foundation
import Testing
@testable import MB_Admin

@Suite("similaridade de título de produto")
struct ProductSimilarityTests {
    @Test("títulos idênticos pontuam 1")
    func titulosIdenticos() {
        #expect(ProductSimilarity.score("colar curto prata 925", "colar curto prata 925") == 1)
    }

    @Test("títulos totalmente diferentes pontuam perto de 0")
    func titulosDiferentes() {
        #expect(ProductSimilarity.score("colar curto prata 925", "tênis esportivo masculino azul") == 0)
    }

    @Test("títulos quase iguais (uma palavra a menos) pontuam alto")
    func titulosQuaseIguais() {
        let score = ProductSimilarity.score(
            "colar curto pingente cravejado menino zircônia branca classico ródio",
            "colar curto pingente cravejado menino zircônia branca classico"
        )
        #expect(score > 0.7)
    }

    @Test("maiúsculas e acentos não mudam o score")
    func maiusculasEAcentos() {
        let score = ProductSimilarity.score("Colár Cürto Prata", "colar curto prata")
        #expect(score == 1)
    }

    @Test("ordem das palavras não muda o score")
    func ordemDasPalavras() {
        let score = ProductSimilarity.score("colar curto prata", "prata colar curto")
        #expect(score == 1)
    }

    @Test("título vazio não crasha e pontua 0")
    func tituloVazio() {
        #expect(ProductSimilarity.score("", "colar curto prata") == 0)
        #expect(ProductSimilarity.score("", "") == 0)
    }

    @Test("plural vs singular (só a letra 's' de diferença) não derruba o score")
    func pluralVersusSingular() {
        #expect(ProductSimilarity.score("colar curto prata", "colares curto prata") == 1)
        #expect(ProductSimilarity.score("brinco argola ouro", "brincos argola ouro") == 1)
    }
}
