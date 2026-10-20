import Foundation
import SwiftData
import Testing
@testable import MB_Admin

@Suite("persistência da lista de produtos sem preço esperto em SwiftData")
struct SwiftDataSmartPriceProductsPersistenceTests {
    private func makeContainer() -> ModelContainer {
        let schema = Schema([SmartPriceProductRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SwiftDataSmartPriceProductsPersistenceTests.\(UUID().uuidString)")!
    }

    private func makeProduct(id: Int) -> SmartPriceProduct {
        SmartPriceProduct(
            id: id, price: 100, minPrice: 70, maxPrice: 150, blocked: false, smartPriceEnabled: false,
            statusText: "preço atual", statusColor: "#8F8F8F", photoPublicID: "foto-\(id)"
        )
    }

    @Test("sem nada salvo ainda, devolve lista vazia")
    func semNadaSalvo() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        #expect(persistence.loadItems().isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, na mesma ordem")
    func salvaELeDeVolta() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        let items = [makeProduct(id: 1), makeProduct(id: 2)]

        persistence.saveItems(items)

        #expect(persistence.loadItems() == items)
    }

    @Test("salvar de novo substitui a lista anterior, não acumula")
    func salvarDeNovoSubstitui() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([makeProduct(id: 1), makeProduct(id: 2)])

        persistence.saveItems([makeProduct(id: 3)])

        #expect(persistence.loadItems().map(\.id) == [3])
    }

    @Test("duas contas com containers separados não compartilham nada")
    func duasContasComContainersSeparadosNaoCompartilhamNada() {
        let persistenceA = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        let persistenceB = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistenceA.saveItems([makeProduct(id: 1)])

        #expect(persistenceB.loadItems().isEmpty)
    }

    @Test("clearItems apaga tudo")
    func clearItemsApagaTudo() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([makeProduct(id: 1)])

        persistence.clearItems()

        #expect(persistence.loadItems().isEmpty)
    }

    @Test("appendPage acrescenta sem apagar o que já tinha, gravando o título resolvido")
    func appendPageGravaTituloResolvido() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        let titles = [1: "brinco argola", 2: "colar prata"]

        persistence.appendPage([makeProduct(id: 1)], startingAt: 0) { titles[$0] }
        persistence.appendPage([makeProduct(id: 2)], startingAt: 1) { titles[$0] }

        #expect(persistence.loadItems().map(\.id) == [1, 2])
        #expect(persistence.search(matching: "argola", limit: 500).map(\.id) == [1])
    }

    @Test("sem título resolvido ainda, appendPage grava vazio — não trava, só não é encontrado pela busca")
    func appendPageSemResolverGravaVazio() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())

        persistence.appendPage([makeProduct(id: 1)], startingAt: 0) { _ in nil }

        #expect(persistence.loadItems().map(\.id) == [1])
        #expect(persistence.search(matching: "qualquer coisa", limit: 500).isEmpty)
    }

    @Test("backfillTitles conserta registros gravados sem título, quando o resolvedor passa a responder")
    func backfillTitlesConsertaRegistros() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.appendPage([makeProduct(id: 1)], startingAt: 0) { _ in nil }
        #expect(persistence.search(matching: "argola", limit: 500).isEmpty)

        persistence.backfillTitles(resolver: { $0 == 1 ? "brinco argola" : nil })

        #expect(persistence.search(matching: "argola", limit: 500).map(\.id) == [1])
    }

    @Test("search respeita o fetchLimit")
    func searchRespeitaOFetchLimit() {
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.appendPage((1...5).map { makeProduct(id: $0) }, startingAt: 0) { "produto \($0)" }

        #expect(persistence.search(matching: "", limit: 3).count == 3)
    }

    @Test("descarta registros existentes quando a versão de esquema salva está desatualizada")
    func descartaRegistrosComVersaoDesatualizada() {
        let accountID = EnjoeiAccountID()
        let container = makeContainer()
        let defaults = makeDefaults()
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: accountID, container: container, defaults: defaults)
        persistence.saveItems([makeProduct(id: 1)])
        defaults.set(0, forKey: "smartPrice.schemaVersion.\(accountID)")

        let migratedPersistence = SwiftDataSmartPriceProductsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(migratedPersistence.loadItems().isEmpty)
    }

    @Test("não descarta de novo quando a versão de esquema já está atualizada")
    func naoDescartaDeNovoQuandoVersaoJaAtualizada() {
        let accountID = EnjoeiAccountID()
        let container = makeContainer()
        let defaults = makeDefaults()
        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: accountID, container: container, defaults: defaults)
        persistence.saveItems([makeProduct(id: 1)])

        let secondPersistence = SwiftDataSmartPriceProductsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(secondPersistence.loadItems().map(\.id) == [1])
    }

    @Test("migra a lista salva pela versão antiga (UserDefaults) uma única vez")
    func migraListaLegada() {
        let accountID = EnjoeiAccountID()
        let defaults = makeDefaults()
        let legacyItems = [makeProduct(id: 1), makeProduct(id: 2)]
        defaults.set(try! JSONEncoder().encode(legacyItems), forKey: "smartPrice.items.\(accountID)")
        let container = makeContainer()

        let persistence = SwiftDataSmartPriceProductsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(persistence.loadItems() == legacyItems)
        #expect(defaults.object(forKey: "smartPrice.items.\(accountID)") == nil)

        let secondPersistence = SwiftDataSmartPriceProductsPersistence(accountID: accountID, container: container, defaults: defaults)
        #expect(secondPersistence.loadItems().count == 2)
    }
}
