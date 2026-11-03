import Foundation
import Testing
@testable import MB_Admin

@Suite("memória da última comparação entre lojas")
struct ComparisonMatchMemoryTests {
    typealias Fixtures = ComparisonFixtures

    private let storeA = EnjoeiAccountID()
    private let storeB = EnjoeiAccountID()
    private let storeC = EnjoeiAccountID()

    private func product(_ id: Int) -> EnjoeiProduct {
        Fixtures.product(id, title: "produto \(id)", cover: nil)
    }

    @Test("guarda o par nos dois sentidos, cada um pelo produto da loja de origem")
    func guardaNosDoisSentidos() {
        let memory = ComparisonMatchMemory()
        memory.record(Fixtures.result(matches: [Fixtures.match(1, 10)]), accountA: storeA, accountB: storeB)

        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .present)
        #expect(memory.presence(of: 10, from: storeB, to: storeA) == .present)
        // O id do produto de uma loja não vale pela outra.
        #expect(memory.presence(of: 10, from: storeA, to: storeB) == nil)
        #expect(memory.presence(of: 1, from: storeA, to: storeC) == nil)
    }

    @Test("cada estado vira um nível de presença: revisar = pode existir, ausente e não verificado ficam separados")
    func niveisDePresenca() {
        let memory = ComparisonMatchMemory()
        let result = Fixtures.result(
            matches: [Fixtures.match(1, 10, status: .confirmed)],
            reviews: [Fixtures.match(2, 20, status: .needsReview)],
            rejected: [Fixtures.match(3, 30, status: .rejected)],
            missingInB: [product(4), product(3)],
            missingInA: [product(40)],
            unverifiedA: [UnverifiedListing(product: product(5), reasons: [.detailsUnavailable])]
        )
        memory.record(result, accountA: storeA, accountB: storeB)

        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .present)
        #expect(memory.presence(of: 2, from: storeA, to: storeB) == .possible)
        #expect(memory.presence(of: 20, from: storeB, to: storeA) == .possible)
        #expect(memory.presence(of: 4, from: storeA, to: storeB) == .possiblyMissing)
        #expect(memory.presence(of: 40, from: storeB, to: storeA) == .possiblyMissing)
        #expect(memory.presence(of: 5, from: storeA, to: storeB) == .unverified)
        // Marcado como diferente de um produto de B, e sem outro par: segue possivelmente ausente.
        #expect(memory.presence(of: 3, from: storeA, to: storeB) == .possiblyMissing)
    }

    @Test("um produto em dois estados fica com o mais forte (par vence revisão)")
    func estadoMaisForteVence() {
        let memory = ComparisonMatchMemory()
        let result = Fixtures.result(
            matches: [Fixtures.match(1, 10)],
            reviews: [Fixtures.match(1, 11, status: .needsReview)]
        )
        memory.record(result, accountA: storeA, accountB: storeB)
        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .present)
        #expect(memory.presence(of: 11, from: storeB, to: storeA) == .possible)
    }

    @Test("a comparação nova entre as mesmas lojas substitui a anterior, inclusive esquecendo pares")
    func comparacaoNovaSubstitui() {
        let memory = ComparisonMatchMemory()
        memory.record(Fixtures.result(matches: [Fixtures.match(1, 10)]), accountA: storeA, accountB: storeB)
        // Comparadas de novo, na ordem inversa, sem o par de antes.
        memory.record(Fixtures.result(matches: [Fixtures.match(20, 2)]), accountA: storeB, accountB: storeA)

        #expect(memory.presence(of: 1, from: storeA, to: storeB) == nil)
        #expect(memory.presence(of: 2, from: storeA, to: storeB) == .present)
        #expect(memory.presence(of: 20, from: storeB, to: storeA) == .present)
    }

    @Test("comparar com outra loja não apaga o que já se sabia da primeira")
    func outraLojaNaoApaga() {
        let memory = ComparisonMatchMemory()
        memory.record(Fixtures.result(matches: [Fixtures.match(1, 10)]), accountA: storeA, accountB: storeB)
        memory.record(Fixtures.result(reviews: [Fixtures.match(1, 30, status: .needsReview)]), accountA: storeA, accountB: storeC)

        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .present)
        #expect(memory.presence(of: 1, from: storeA, to: storeC) == .possible)
    }

    @Test("esquecer uma conta tira tudo que envolve ela, nos dois sentidos")
    func esquecerConta() {
        let memory = ComparisonMatchMemory()
        memory.record(Fixtures.result(matches: [Fixtures.match(1, 10)]), accountA: storeA, accountB: storeB)
        memory.record(Fixtures.result(reviews: [Fixtures.match(1, 30, status: .needsReview)]), accountA: storeA, accountB: storeC)

        memory.forget(accountID: storeB)

        #expect(memory.presence(of: 1, from: storeA, to: storeB) == nil)
        #expect(memory.presence(of: 10, from: storeB, to: storeA) == nil)
        #expect(memory.presence(of: 1, from: storeA, to: storeC) == .possible)
    }
}
