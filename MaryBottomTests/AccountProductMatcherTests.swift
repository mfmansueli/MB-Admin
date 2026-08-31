import Foundation
import Testing
@testable import MaryBottom

@Suite("comparação de produtos entre duas contas")
struct AccountProductMatcherTests {
    @Test("produtos com título parecido acima do threshold viram par")
    func parVirouMatch() {
        let a = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925 zircônia branca")
        let b = EnjoeiFixtures.product(id: 2, title: "colar curto prata 925 zircônia")

        let result = AccountProductMatcher.compare(productsA: [a], productsB: [b])

        #expect(result.matches.count == 1)
        #expect(result.matches.first?.productA.id == 1)
        #expect(result.matches.first?.productB.id == 2)
        #expect(result.onlyInA.isEmpty)
        #expect(result.onlyInB.isEmpty)
    }

    @Test("título muito diferente não vira par")
    func naoVirouMatch() {
        let a = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925")
        let b = EnjoeiFixtures.product(id: 2, title: "tênis esportivo masculino azul")

        let result = AccountProductMatcher.compare(productsA: [a], productsB: [b])

        #expect(result.matches.isEmpty)
        #expect(result.onlyInA.map(\.id) == [1])
        #expect(result.onlyInB.map(\.id) == [2])
    }

    @Test("produto sem correspondente cai em onlyInA/onlyInB")
    func semCorrespondente() {
        let a1 = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925")
        let a2 = EnjoeiFixtures.product(id: 2, title: "brinco argola ouro")
        let b1 = EnjoeiFixtures.product(id: 3, title: "colar curto prata 925")

        let result = AccountProductMatcher.compare(productsA: [a1, a2], productsB: [b1])

        #expect(result.matches.map(\.productA.id) == [1])
        #expect(result.onlyInA.map(\.id) == [2])
        #expect(result.onlyInB.isEmpty)
    }

    @Test("dois produtos de A parecidos com o mesmo produto de B: só o de maior score casa")
    func casamentoGulosoResolveConflito() {
        // b combina melhor com a1 (título idêntico) do que com a2 (uma palavra a menos).
        let a1 = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925 zircônia branca")
        let a2 = EnjoeiFixtures.product(id: 2, title: "colar curto prata 925 zircônia")
        let b = EnjoeiFixtures.product(id: 3, title: "colar curto prata 925 zircônia branca")

        let result = AccountProductMatcher.compare(productsA: [a1, a2], productsB: [b], threshold: 0.5)

        #expect(result.matches.count == 1)
        #expect(result.matches.first?.productA.id == 1)
        #expect(result.matches.first?.productB.id == 3)
        #expect(result.onlyInA.map(\.id) == [2])
        #expect(result.onlyInB.isEmpty)
    }

    @Test("lista vazia de um dos lados: tudo cai sem par, sem crash")
    func listaVaziaDeUmLado() {
        let a = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925")

        let result = AccountProductMatcher.compare(productsA: [a], productsB: [])

        #expect(result.matches.isEmpty)
        #expect(result.onlyInA.map(\.id) == [1])
        #expect(result.onlyInB.isEmpty)

        let resultBothEmpty = AccountProductMatcher.compare(productsA: [], productsB: [])
        #expect(resultBothEmpty.matches.isEmpty)
        #expect(resultBothEmpty.onlyInA.isEmpty)
        #expect(resultBothEmpty.onlyInB.isEmpty)
    }

    @Test("threshold customizado muda o resultado")
    func thresholdCustomizado() {
        let a = EnjoeiFixtures.product(id: 1, title: "colar curto prata 925 zircônia branca clássico")
        let b = EnjoeiFixtures.product(id: 2, title: "colar dourado")

        let permissive = AccountProductMatcher.compare(productsA: [a], productsB: [b], threshold: 0.05)
        let strict = AccountProductMatcher.compare(productsA: [a], productsB: [b], threshold: 0.9)

        #expect(permissive.matches.count == 1)
        #expect(strict.matches.isEmpty)
    }
}
