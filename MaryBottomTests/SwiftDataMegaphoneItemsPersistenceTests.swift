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
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        #expect(persistence.loadItems().isEmpty)
    }

    @Test("guarda e lê de volta produto e exposição, na mesma ordem")
    func salvaELeDeVolta() {
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        let exposure = MegaphoneExposure(
            productID: 2, kind: .maximumAfterDiscount, priceToIncreaseExposure: 90, discountLabel: "- 40%"
        )
        let items = [makeItem(id: 1), makeItem(id: 2, exposure: exposure)]

        persistence.saveItems(items)

        #expect(persistence.loadItems() == items)
    }

    /// `status` nunca é persistido de verdade — no momento em que `saveItems` roda (logo depois de
    /// carregar a loja, ver `MegaphoneRunner.setLoadedItems`), nenhum produto já foi megafonado
    /// ainda, e nenhuma megafonagem em andamento chega a ser salva (só existe ao vivo em
    /// `MegaphoneRunner.items`) — então reconstruir sempre como `.pending` é fiel ao que sempre foi
    /// salvo, mesmo que quem chamou `saveItems` tenha passado um status diferente.
    @Test("status não sobrevive ao salvar e reler — sempre volta pending")
    func statusNaoSobreviveAoSalvarERelerSempreVoltaPending() {
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([makeItem(id: 1, status: .succeeded), makeItem(id: 2, status: .failed("erro"))])

        let reloaded = persistence.loadItems()

        #expect(reloaded.map(\.status) == [.pending, .pending])
    }

    @Test("salvar de novo substitui a lista anterior, não acumula")
    func salvarDeNovoSubstitui() {
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([makeItem(id: 1), makeItem(id: 2)])

        persistence.saveItems([makeItem(id: 3)])

        #expect(persistence.loadItems().map(\.id) == [3])
    }

    @Test("duas contas com containers separados não compartilham nada")
    func duasContasComContainersSeparadosNaoCompartilhamNada() {
        let persistenceA = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        let persistenceB = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistenceA.saveItems([makeItem(id: 1)])

        #expect(persistenceB.loadItems().isEmpty)
    }

    @Test("clearItems apaga tudo")
    func clearItemsApagaTudo() {
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([makeItem(id: 1)])

        persistence.clearItems()

        #expect(persistence.loadItems().isEmpty)
    }

    @Test("searchProductIDs encontra por título, sem diferenciar maiúsculas/minúsculas, respeitando o fetchLimit")
    func searchProductIDsEncontraPorTitulo() {
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([
            MegaphoneItem(product: EnjoeiProduct(id: 1, title: "Brinco Argola", path: "p1", photoPublicID: nil, currentPrice: 100, originalPrice: 100)),
            MegaphoneItem(product: EnjoeiProduct(id: 2, title: "colar prata", path: "p2", photoPublicID: nil, currentPrice: 100, originalPrice: 100))
        ])

        #expect(persistence.searchProductIDs(matching: "argola", limit: 500) == [1])
        #expect(persistence.searchProductIDs(matching: "PRATA", limit: 500) == [2])
        #expect(persistence.searchProductIDs(matching: "inexistente", limit: 500).isEmpty)
        #expect(persistence.searchProductIDs(matching: "", limit: 1).count == 1)
    }

    @Test("descarta registros existentes quando a versão de esquema salva está desatualizada")
    func descartaRegistrosComVersaoDesatualizada() {
        let accountID = EnjoeiAccountID()
        let container = makeContainer()
        let defaults = makeDefaults()
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: accountID, container: container, defaults: defaults)
        persistence.saveItems([makeItem(id: 1)])
        defaults.set(0, forKey: "megaphone.schemaVersion.\(accountID)")

        let migratedPersistence = SwiftDataMegaphoneItemsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(migratedPersistence.loadItems().isEmpty)
    }

    @Test("não descarta de novo quando a versão de esquema já está atualizada")
    func naoDescartaDeNovoQuandoVersaoJaAtualizada() {
        let accountID = EnjoeiAccountID()
        let container = makeContainer()
        let defaults = makeDefaults()
        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: accountID, container: container, defaults: defaults)
        persistence.saveItems([makeItem(id: 1)])

        let secondPersistence = SwiftDataMegaphoneItemsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(secondPersistence.loadItems().map(\.id) == [1])
    }

    @Test("migra a lista salva pela versão antiga (UserDefaults) uma única vez")
    func migraListaLegada() {
        let accountID = EnjoeiAccountID()
        let defaults = makeDefaults()
        let legacyItems = [makeItem(id: 1), makeItem(id: 2)]
        defaults.set(try! JSONEncoder().encode(legacyItems), forKey: "megaphone.items.\(accountID)")
        let container = makeContainer()

        let persistence = SwiftDataMegaphoneItemsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(persistence.loadItems() == legacyItems)
        #expect(defaults.object(forKey: "megaphone.items.\(accountID)") == nil)

        let secondPersistence = SwiftDataMegaphoneItemsPersistence(accountID: accountID, container: container, defaults: defaults)
        #expect(secondPersistence.loadItems().count == 2)
    }
}
