import Foundation
import Testing
@testable import MaryBottom

@Suite("persistência do histórico da fila em UserDefaults")
struct UserDefaultsPostHistoryPersistenceTests {
    /// Suite efêmera própria por teste, pra não sujar (nem depender de) o `UserDefaults.standard`
    /// da máquina rodando os testes.
    private func makePersistence() -> UserDefaultsPostHistoryPersistence {
        let suiteName = "UserDefaultsPostHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsPostHistoryPersistence(defaults: defaults)
    }

    private func makeEntry(id: Int, kind: PostQueueItem.Kind, outcome: PostHistoryEntry.Outcome) -> PostHistoryEntry {
        PostHistoryEntry(
            id: UUID(),
            product: EnjoeiProduct(
                id: id,
                title: "produto \(id)",
                path: "produto-\(id)",
                photoPublicID: "foto-\(id)",
                currentPrice: 100,
                originalPrice: 150
            ),
            kind: kind,
            sourceAccountID: EnjoeiAccountID(),
            sourceAccountName: "origem",
            destinationAccountID: EnjoeiAccountID(),
            destinationAccountName: "destino",
            outcome: outcome,
            completedAt: .now
        )
    }

    @Test("sem nada salvo ainda, devolve lista vazia")
    func semNadaSalvo() {
        #expect(makePersistence().loadEntries().isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, inclusive erro e os quatro tipos de ação")
    func salvaELeDeVolta() {
        let persistence = makePersistence()
        let entries = [
            makeEntry(id: 1, kind: .post, outcome: .succeeded),
            makeEntry(id: 2, kind: .delete, outcome: .failed("o enjoei caiu")),
            makeEntry(id: 3, kind: .inactivate, outcome: .succeeded),
            makeEntry(id: 4, kind: .activate, outcome: .succeeded)
        ]

        persistence.save(entries)

        #expect(persistence.loadEntries() == entries)
    }
}
