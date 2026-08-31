import Foundation
import Testing
@testable import MaryBottom

@Suite("persistência da lista de produtos em UserDefaults")
struct UserDefaultsMegaphoneItemsPersistenceTests {
    /// Suite efêmera própria por teste, pra não sujar (nem depender de) o `UserDefaults.standard`
    /// da máquina rodando os testes.
    private func makePersistence() -> UserDefaultsMegaphoneItemsPersistence {
        let suiteName = "UserDefaultsMegaphoneItemsPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsMegaphoneItemsPersistence(defaults: defaults)
    }

    private func makeItem(id: Int, status: MegaphoneStatus, exposure: MegaphoneExposure?) -> MegaphoneItem {
        MegaphoneItem(
            product: EnjoeiProduct(
                id: id,
                title: "produto \(id)",
                path: "produto-\(id)",
                photoPublicID: "foto-\(id)",
                currentPrice: 100,
                originalPrice: 150
            ),
            status: status,
            exposure: exposure
        )
    }

    @Test("sem nada salvo ainda, devolve lista vazia")
    func semNadaSalvo() {
        let persistence = makePersistence()
        #expect(persistence.loadItems(accountID: EnjoeiAccountID()).isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, inclusive status falho e exposição")
    func salvaELeDeVolta() {
        let persistence = makePersistence()
        let accountID = EnjoeiAccountID()
        let items = [
            makeItem(id: 1, status: .succeeded, exposure: nil),
            makeItem(
                id: 2,
                status: .failed("preço mínimo não atingido"),
                exposure: MegaphoneExposure(
                    productID: 2, kind: .maximumAfterDiscount, priceToIncreaseExposure: 90, discountLabel: "- 40%"
                )
            )
        ]

        persistence.saveItems(items, accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID) == items)
    }

    @Test("cada conta tem sua própria chave, sem vazar pra outra")
    func chavesSeparadasPorConta() {
        let persistence = makePersistence()
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeItem(id: 1, status: .pending, exposure: nil)], accountID: accountA)

        #expect(persistence.loadItems(accountID: accountB).isEmpty)
    }

    @Test("clearItems apaga só a lista da conta pedida")
    func clearItemsApagaSoAConta() {
        let persistence = makePersistence()
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeItem(id: 1, status: .pending, exposure: nil)], accountID: accountA)
        persistence.saveItems([makeItem(id: 2, status: .pending, exposure: nil)], accountID: accountB)

        persistence.clearItems(accountID: accountA)

        #expect(persistence.loadItems(accountID: accountA).isEmpty)
        #expect(persistence.loadItems(accountID: accountB).map(\.id) == [2])
    }
}
