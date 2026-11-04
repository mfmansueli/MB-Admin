import Foundation
import Testing
@testable import MB_Admin

/// A regra de "o que está no ar" — só anúncios publicados entram na comparação.
@Suite("só anúncios publicados contam na comparação")
struct PublishedListingFilterTests {
    private let listedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let accountA = EnjoeiAccountID()
    private let accountB = EnjoeiAccountID()

    private func change(_ id: Int, _ state: ListingStateChange.State, minutes: Double) -> ListingStateChange {
        ListingStateChange(productID: id, state: state, date: listedAt.addingTimeInterval(minutes * 60))
    }

    private func unpublished(_ changes: [ListingStateChange], listed: [Int] = [1, 2, 3]) -> Set<Int> {
        PublishedListingFilter.unpublished(listedIDs: listed, listedAt: listedAt, changes: changes)
    }

    private func entry(_ id: Int, _ kind: PostQueueItem.Kind, account: EnjoeiAccountID, outcome: PostHistoryEntry.Outcome = .succeeded) -> PostHistoryEntry {
        PostHistoryEntry(
            id: UUID(),
            product: ComparisonFixtures.product(id, title: "anel", cover: "a\(id)"),
            kind: kind,
            sourceAccountID: account,
            sourceAccountName: "antonia",
            destinationAccountID: account,
            destinationAccountName: "antonia",
            outcome: outcome,
            completedAt: listedAt
        )
    }

    @Test("sem nada visto depois da listagem, tudo que veio nela está publicado")
    func semMudancas() {
        #expect(unpublished([]).isEmpty)
        #expect(unpublished([change(9, .inactive, minutes: 5)]).isEmpty)
    }

    @Test("inativado depois da listagem sai")
    func inativadoDepois() {
        #expect(unpublished([change(2, .inactive, minutes: 5)]) == [2])
    }

    @Test("inativado pouco antes da listagem também sai — a busca da loja pode demorar pra tirar da vitrine")
    func inativadoPoucoAntes() {
        #expect(unpublished([change(2, .inactive, minutes: -10)]) == [2])
    }

    @Test("inativado muito antes e ainda na listagem: foi ativado de novo por fora, a listagem vale")
    func inativadoMuitoAntes() {
        let minutes = -(PublishedListingFilter.searchLagGrace / 60) - 1
        #expect(unpublished([change(2, .inactive, minutes: minutes)]).isEmpty)
    }

    @Test("apagado nunca volta, não importa quando foi")
    func apagadoSempreSai() {
        #expect(unpublished([change(1, .deleted, minutes: -10_000)]) == [1])
        // Nem uma ativação depois (não existe ativar apagado) traz de volta.
        #expect(unpublished([change(1, .deleted, minutes: -5), change(1, .published, minutes: 5)]) == [1])
    }

    @Test("ativado depois de inativado volta a valer a listagem; vale sempre a mudança mais recente")
    func maisRecenteVale() {
        #expect(unpublished([change(3, .inactive, minutes: 1), change(3, .published, minutes: 2)]).isEmpty)
        #expect(unpublished([change(3, .published, minutes: 2), change(3, .inactive, minutes: 3)]) == [3])
    }

    @Test("da fila só contam apagar, inativar e ativar que deram certo, da própria conta")
    func historicoDaFila() {
        let changes = ListingStateChange.history([
            entry(1, .inactivate, account: accountA),
            entry(2, .delete, account: accountA),
            entry(3, .activate, account: accountA),
            entry(4, .post, account: accountA),
            entry(5, .inactivate, account: accountA, outcome: .failed("HTTP 500")),
            entry(6, .delete, account: accountB)
        ], accountID: accountA)

        #expect(changes.map(\.productID) == [1, 2, 3])
        #expect(changes.map(\.state) == [.inactive, .deleted, .published])
        #expect(changes.allSatisfy { $0.date == listedAt })
    }

    @Test("a aba inativos diz que cada produto da lista estava inativo quando ela foi buscada")
    func abaInativos() {
        let changes = ListingStateChange.inactiveList([7, 8], loadedAt: listedAt)
        #expect(changes == [
            ListingStateChange(productID: 7, state: .inactive, date: listedAt),
            ListingStateChange(productID: 8, state: .inactive, date: listedAt)
        ])
    }
}
