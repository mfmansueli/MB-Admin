import Foundation
import Testing
@testable import MB_Admin

@Suite("memória da última comparação entre lojas")
struct ComparisonMatchMemoryTests {
    private let storeA = EnjoeiAccountID()
    private let storeB = EnjoeiAccountID()
    private let storeC = EnjoeiAccountID()

    private func match(_ idA: Int, _ idB: Int, similarity: Double) -> ProductMatch {
        ProductMatch(
            productA: EnjoeiFixtures.product(id: idA),
            productB: EnjoeiFixtures.product(id: idB),
            similarity: similarity
        )
    }

    @Test("guarda o par nos dois sentidos, cada um pelo produto da loja de origem")
    func guardaNosDoisSentidos() {
        let memory = ComparisonMatchMemory()
        memory.record([match(1, 10, similarity: 0.82)], accountA: storeA, accountB: storeB)

        #expect(memory.similarity(of: 1, from: storeA, to: storeB) == 0.82)
        #expect(memory.similarity(of: 10, from: storeB, to: storeA) == 0.82)
        // O id do produto de uma loja não vale pela outra.
        #expect(memory.similarity(of: 10, from: storeA, to: storeB) == nil)
        #expect(memory.similarity(of: 1, from: storeA, to: storeC) == nil)
    }

    @Test("a comparação nova entre as mesmas lojas substitui a anterior, inclusive esquecendo pares")
    func comparacaoNovaSubstitui() {
        let memory = ComparisonMatchMemory()
        memory.record([match(1, 10, similarity: 0.9)], accountA: storeA, accountB: storeB)
        // Comparadas de novo, na ordem inversa, sem o par de antes.
        memory.record([match(20, 2, similarity: 0.7)], accountA: storeB, accountB: storeA)

        #expect(memory.similarity(of: 1, from: storeA, to: storeB) == nil)
        #expect(memory.similarity(of: 2, from: storeA, to: storeB) == 0.7)
        #expect(memory.similarity(of: 20, from: storeB, to: storeA) == 0.7)
    }

    @Test("comparar com outra loja não apaga o que já se sabia da primeira")
    func outraLojaNaoApaga() {
        let memory = ComparisonMatchMemory()
        memory.record([match(1, 10, similarity: 0.9)], accountA: storeA, accountB: storeB)
        memory.record([match(1, 30, similarity: 0.6)], accountA: storeA, accountB: storeC)

        #expect(memory.similarity(of: 1, from: storeA, to: storeB) == 0.9)
        #expect(memory.similarity(of: 1, from: storeA, to: storeC) == 0.6)
    }

    @Test("par abaixo de 50% não vale como aviso")
    func abaixoDoLimiteNaoVale() {
        let memory = ComparisonMatchMemory()
        memory.record([match(1, 10, similarity: 0.49)], accountA: storeA, accountB: storeB)

        #expect(memory.similarity(of: 1, from: storeA, to: storeB) == nil)
    }

    @Test("esquecer uma conta tira tudo que envolve ela, nos dois sentidos")
    func esquecerConta() {
        let memory = ComparisonMatchMemory()
        memory.record([match(1, 10, similarity: 0.9)], accountA: storeA, accountB: storeB)
        memory.record([match(1, 30, similarity: 0.6)], accountA: storeA, accountB: storeC)

        memory.forget(accountID: storeB)

        #expect(memory.similarity(of: 1, from: storeA, to: storeB) == nil)
        #expect(memory.similarity(of: 10, from: storeB, to: storeA) == nil)
        #expect(memory.similarity(of: 1, from: storeA, to: storeC) == 0.6)
    }
}
