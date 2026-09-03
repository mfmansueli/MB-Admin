import Foundation
import Testing
@testable import MaryBottom

@Suite("persistência dos itens pendentes da fila em UserDefaults")
struct UserDefaultsPostQueueItemsPersistenceTests {
    /// Suite efêmera própria por teste, pra não sujar (nem depender de) o `UserDefaults.standard`
    /// da máquina rodando os testes.
    private func makePersistence() -> UserDefaultsPostQueueItemsPersistence {
        let suiteName = "UserDefaultsPostQueueItemsPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsPostQueueItemsPersistence(defaults: defaults)
    }

    @Test("sem nada salvo ainda, devolve lista vazia")
    func semNadaSalvo() {
        #expect(makePersistence().loadItems().isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, inclusive os quatro tipos de ação")
    func salvaELeDeVolta() {
        let persistence = makePersistence()
        let items = [
            PostQueueItem(
                id: UUID(), product: EnjoeiFixtures.product(id: 1), kind: .post,
                sourceAccountID: UUID(), sourceAccountName: "origem",
                destinationAccountID: UUID(), destinationAccountName: "destino"
            ),
            PostQueueItem(
                id: UUID(), product: EnjoeiFixtures.product(id: 2), kind: .delete,
                sourceAccountID: UUID(), sourceAccountName: "origem",
                destinationAccountID: UUID(), destinationAccountName: "origem"
            ),
            PostQueueItem(
                id: UUID(), product: EnjoeiFixtures.product(id: 3), kind: .inactivate,
                sourceAccountID: UUID(), sourceAccountName: "origem",
                destinationAccountID: UUID(), destinationAccountName: "origem"
            ),
            PostQueueItem(
                id: UUID(), product: EnjoeiFixtures.product(id: 4), kind: .activate,
                sourceAccountID: UUID(), sourceAccountName: "origem",
                destinationAccountID: UUID(), destinationAccountName: "origem"
            )
        ]

        persistence.saveItems(items)

        #expect(persistence.loadItems() == items)
    }
}
