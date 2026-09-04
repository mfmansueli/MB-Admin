import Foundation
import SwiftData
import Testing
@testable import MaryBottom

@Suite("persistência da lista de produtos do megafone em SwiftData")
struct SwiftDataMegaphoneItemsPersistenceTests {
    private func makeContainer() -> ModelContainer {
        let schema = Schema([MegaphoneItemRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SwiftDataMegaphoneItemsPersistenceTests.\(UUID().uuidString)")!
    }

    private func makeItem(id: Int, status: MegaphoneStatus = .pending, exposure: MegaphoneExposure? = nil) -> MegaphoneItem {
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
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        #expect(persistence.loadItems(accountID: EnjoeiAccountID()).isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, inclusive status falho e exposição, na mesma ordem")
    func salvaELeDeVolta() {
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        let items = [
            makeItem(id: 1, status: .succeeded),
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

    @Test("salvar de novo substitui a lista anterior da conta, não acumula")
    func salvarDeNovoSubstitui() {
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        persistence.saveItems([makeItem(id: 1), makeItem(id: 2)], accountID: accountID)

        persistence.saveItems([makeItem(id: 3)], accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID).map(\.id) == [3])
    }

    @Test("cada conta tem seus próprios registros, sem vazar pra outra")
    func registrosSeparadosPorConta() {
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeItem(id: 1)], accountID: accountA)

        #expect(persistence.loadItems(accountID: accountB).isEmpty)
    }

    @Test("clearItems apaga só a lista da conta pedida")
    func clearItemsApagaSoAConta() {
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeItem(id: 1)], accountID: accountA)
        persistence.saveItems([makeItem(id: 2)], accountID: accountB)

        persistence.clearItems(accountID: accountA)

        #expect(persistence.loadItems(accountID: accountA).isEmpty)
        #expect(persistence.loadItems(accountID: accountB).map(\.id) == [2])
    }

    @Test("migra a lista salva pela versão antiga (UserDefaults) uma única vez, só da conta lida")
    func migraListaLegada() {
        let defaults = makeDefaults()
        let accountID = EnjoeiAccountID()
        let legacyItems = [makeItem(id: 1), makeItem(id: 2)]
        defaults.set(try! JSONEncoder().encode(legacyItems), forKey: "megaphone.items.\(accountID)")
        let container = makeContainer()

        let persistence = SwiftDataMegaphoneItemsPersistence(container: container, defaults: defaults)

        #expect(persistence.loadItems(accountID: accountID) == legacyItems)
        #expect(defaults.object(forKey: "megaphone.items.\(accountID)") == nil)

        let secondPersistence = SwiftDataMegaphoneItemsPersistence(container: container, defaults: defaults)
        #expect(secondPersistence.loadItems(accountID: accountID).count == 2)
    }
}
