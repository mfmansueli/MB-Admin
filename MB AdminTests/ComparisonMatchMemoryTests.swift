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

    @Test("possivelmente ausente com outra versão na outra loja vira 'outra versão' — informação, não aviso de duplicata")
    func outraVersao() {
        let memory = ComparisonMatchMemory()
        let version = OtherVersion(product: product(20), differences: [])
        let result = Fixtures.result(
            missingInB: [product(1), product(2)],
            missingInA: [product(20)],
            otherVersions: [
                ListingKey(sellerID: Fixtures.sellerA, productID: 1): [version],
                ListingKey(sellerID: Fixtures.sellerB, productID: 20): [OtherVersion(product: product(1), differences: [])]
            ]
        )
        memory.record(result, accountA: storeA, accountB: storeB)
        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .otherVersion)
        #expect(memory.presence(of: 2, from: storeA, to: storeB) == .possiblyMissing)
        #expect(memory.presence(of: 20, from: storeB, to: storeA) == .otherVersion)
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

    // MARK: - Só o que está publicado

    @Test("o par na outra loja saiu da vitrine: o produto passa a possivelmente ausente lá, e o que saiu perde o aviso")
    func parForaDaVitrine() {
        let memory = ComparisonMatchMemory()
        memory.record(Fixtures.result(
            matches: [Fixtures.match(1, 10)],
            reviews: [Fixtures.match(2, 20, status: .needsReview), Fixtures.match(3, 10, status: .needsReview)]
        ), accountA: storeA, accountB: storeB)

        memory.forgetUnpublished([10], in: storeB)

        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .possiblyMissing)
        #expect(memory.presence(of: 3, from: storeA, to: storeB) == .possiblyMissing)
        // O que não tinha nada a ver com o anúncio que saiu fica igual.
        #expect(memory.presence(of: 2, from: storeA, to: storeB) == .possible)
        #expect(memory.presence(of: 20, from: storeB, to: storeA) == .possible)
        // Fora da vitrine, o próprio anúncio não tem mais aviso nenhum.
        #expect(memory.presence(of: 10, from: storeB, to: storeA) == nil)
    }

    @Test("com par forte e revisão em lojas diferentes, só perde o que saiu")
    func continuaComOOutroPar() {
        let memory = ComparisonMatchMemory()
        memory.record(Fixtures.result(
            matches: [Fixtures.match(1, 10)],
            reviews: [Fixtures.match(1, 11, status: .needsReview)]
        ), accountA: storeA, accountB: storeB)

        memory.forgetUnpublished([10], in: storeB)
        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .possible)
        memory.forgetUnpublished([11], in: storeB)
        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .possiblyMissing)
    }

    @Test("sem par e com a lista de lá incompleta, perder o par vira 'não verificado', não ausente")
    func listaIncompletaViraNaoVerificado() {
        let memory = ComparisonMatchMemory()
        let base = Fixtures.result(matches: [Fixtures.match(1, 10)])
        let result = AccountComparisonResult(
            storeA: base.storeA,
            storeB: ComparisonStoreSummary(
                sellerID: Fixtures.sellerB, name: "loja B", status: .incomplete(loaded: 1, expected: 5), listingCount: 1,
                listingsWithPhotoFailures: 0, listingsWithDetailsFailures: 0
            ),
            matches: base.matches
        )
        memory.record(result, accountA: storeA, accountB: storeB)

        memory.forgetUnpublished([10], in: storeB)
        #expect(memory.presence(of: 1, from: storeA, to: storeB) == .unverified)
    }
}
