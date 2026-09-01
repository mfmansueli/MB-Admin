import Foundation
import Testing
@testable import MaryBottom

@Suite("persistência da lista de produtos inativos em UserDefaults")
struct UserDefaultsInactiveProductsPersistenceTests {
    /// Suite efêmera própria por teste, pra não sujar (nem depender de) o `UserDefaults.standard`
    /// da máquina rodando os testes.
    private func makePersistence() -> UserDefaultsInactiveProductsPersistence {
        let suiteName = "UserDefaultsInactiveProductsPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsInactiveProductsPersistence(defaults: defaults)
    }

    private func makeProduct(id: Int) -> InactiveProduct {
        InactiveProduct(
            id: id,
            path: "produto-\(id)",
            title: "produto \(id)",
            price: 100,
            photoPublicID: "foto-\(id)",
            inactiveSince: "01/01/2026"
        )
    }

    @Test("sem nada salvo ainda, devolve lista vazia")
    func semNadaSalvo() {
        let persistence = makePersistence()
        #expect(persistence.loadItems(accountID: EnjoeiAccountID()).isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira")
    func salvaELeDeVolta() {
        let persistence = makePersistence()
        let accountID = EnjoeiAccountID()
        let items = [makeProduct(id: 1), makeProduct(id: 2)]

        persistence.saveItems(items, accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID) == items)
    }

    @Test("cada conta tem sua própria chave, sem vazar pra outra")
    func chavesSeparadasPorConta() {
        let persistence = makePersistence()
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1)], accountID: accountA)

        #expect(persistence.loadItems(accountID: accountB).isEmpty)
    }

    @Test("clearItems apaga só a lista da conta pedida")
    func clearItemsApagaSoAConta() {
        let persistence = makePersistence()
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1)], accountID: accountA)
        persistence.saveItems([makeProduct(id: 2)], accountID: accountB)

        persistence.clearItems(accountID: accountA)

        #expect(persistence.loadItems(accountID: accountA).isEmpty)
        #expect(persistence.loadItems(accountID: accountB).map(\.id) == [2])
    }
}
