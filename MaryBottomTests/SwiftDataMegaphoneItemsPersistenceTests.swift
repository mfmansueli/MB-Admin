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

    @Test("guarda e lê de volta produto e exposição, na mesma ordem")
    func salvaELeDeVolta() {
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        let exposure = MegaphoneExposure(
            productID: 2, kind: .maximumAfterDiscount, priceToIncreaseExposure: 90, discountLabel: "- 40%"
        )
        let items = [makeItem(id: 1), makeItem(id: 2, exposure: exposure)]

        persistence.saveItems(items, accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID) == items)
    }

    /// `status` nunca é persistido de verdade — no momento em que `saveItems` roda (logo depois de
    /// carregar a loja, ver `MegaphoneRunner.setLoadedItems`), nenhum produto já foi megafonado
    /// ainda, e nenhuma megafonagem em andamento chega a ser salva (só existe ao vivo em
    /// `MegaphoneRunner.items`) — então reconstruir sempre como `.pending` é fiel ao que sempre foi
    /// salvo, mesmo que quem chamou `saveItems` tenha passado um status diferente.
    @Test("status não sobrevive ao salvar e reler — sempre volta pending")
    func statusNaoSobreviveAoSalvarERelerSempreVoltaPending() {
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        persistence.saveItems(
            [makeItem(id: 1, status: .succeeded), makeItem(id: 2, status: .failed("erro"))],
            accountID: accountID
        )

        let reloaded = persistence.loadItems(accountID: accountID)

        #expect(reloaded.map(\.status) == [.pending, .pending])
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

    @Test("searchProductIDs encontra por título, sem diferenciar maiúsculas/minúsculas, respeitando o fetchLimit")
    func searchProductIDsEncontraPorTitulo() {
        let persistence = SwiftDataMegaphoneItemsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        persistence.saveItems(
            [
                MegaphoneItem(product: EnjoeiProduct(id: 1, title: "Brinco Argola", path: "p1", photoPublicID: nil, currentPrice: 100, originalPrice: 100)),
                MegaphoneItem(product: EnjoeiProduct(id: 2, title: "colar prata", path: "p2", photoPublicID: nil, currentPrice: 100, originalPrice: 100))
            ],
            accountID: accountID
        )

        #expect(persistence.searchProductIDs(matching: "argola", accountID: accountID, limit: 500) == [1])
        #expect(persistence.searchProductIDs(matching: "PRATA", accountID: accountID, limit: 500) == [2])
        #expect(persistence.searchProductIDs(matching: "inexistente", accountID: accountID, limit: 500).isEmpty)
        #expect(persistence.searchProductIDs(matching: "", accountID: accountID, limit: 1).count == 1)
    }

    @Test("descarta registros existentes quando a versão de esquema salva está desatualizada")
    func descartaRegistrosComVersaoDesatualizada() {
        let container = makeContainer()
        let defaults = makeDefaults()
        let accountID = EnjoeiAccountID()
        let persistence = SwiftDataMegaphoneItemsPersistence(container: container, defaults: defaults)
        persistence.saveItems([makeItem(id: 1)], accountID: accountID)
        defaults.set(0, forKey: "megaphone.schemaVersion")

        let migratedPersistence = SwiftDataMegaphoneItemsPersistence(container: container, defaults: defaults)

        #expect(migratedPersistence.loadItems(accountID: accountID).isEmpty)
    }

    @Test("não descarta de novo quando a versão de esquema já está atualizada")
    func naoDescartaDeNovoQuandoVersaoJaAtualizada() {
        let container = makeContainer()
        let defaults = makeDefaults()
        let accountID = EnjoeiAccountID()
        let persistence = SwiftDataMegaphoneItemsPersistence(container: container, defaults: defaults)
        persistence.saveItems([makeItem(id: 1)], accountID: accountID)

        let secondPersistence = SwiftDataMegaphoneItemsPersistence(container: container, defaults: defaults)

        #expect(secondPersistence.loadItems(accountID: accountID).map(\.id) == [1])
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
