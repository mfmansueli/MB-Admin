import Foundation
import SwiftData
import Testing
@testable import MaryBottom

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
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        #expect(persistence.loadItems(accountID: EnjoeiAccountID()).isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, na mesma ordem")
    func salvaELeDeVolta() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        let items = [makeProduct(id: 1), makeProduct(id: 2)]

        persistence.saveItems(items, accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID) == items)
    }

    @Test("salvar de novo substitui a lista anterior da conta, não acumula")
    func salvarDeNovoSubstitui() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1), makeProduct(id: 2)], accountID: accountID)

        persistence.saveItems([makeProduct(id: 3)], accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID).map(\.id) == [3])
    }

    @Test("cada conta tem seus próprios registros, sem vazar pra outra")
    func registrosSeparadosPorConta() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1)], accountID: accountA)

        #expect(persistence.loadItems(accountID: accountB).isEmpty)
    }

    @Test("clearItems apaga só a lista da conta pedida")
    func clearItemsApagaSoAConta() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1)], accountID: accountA)
        persistence.saveItems([makeProduct(id: 2)], accountID: accountB)

        persistence.clearItems(accountID: accountA)

        #expect(persistence.loadItems(accountID: accountA).isEmpty)
        #expect(persistence.loadItems(accountID: accountB).map(\.id) == [2])
    }

    @Test("appendPage acrescenta sem apagar o que já tinha, gravando o título resolvido")
    func appendPageGravaTituloResolvido() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        let titles = [1: "brinco argola", 2: "colar prata"]

        persistence.appendPage([makeProduct(id: 1)], startingAt: 0, accountID: accountID) { titles[$0] }
        persistence.appendPage([makeProduct(id: 2)], startingAt: 1, accountID: accountID) { titles[$0] }

        #expect(persistence.loadItems(accountID: accountID).map(\.id) == [1, 2])
        #expect(persistence.search(matching: "argola", accountID: accountID, limit: 500).map(\.id) == [1])
    }

    @Test("sem título resolvido ainda, appendPage grava vazio — não trava, só não é encontrado pela busca")
    func appendPageSemResolverGravaVazio() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()

        persistence.appendPage([makeProduct(id: 1)], startingAt: 0, accountID: accountID) { _ in nil }

        #expect(persistence.loadItems(accountID: accountID).map(\.id) == [1])
        #expect(persistence.search(matching: "qualquer coisa", accountID: accountID, limit: 500).isEmpty)
    }

    @Test("backfillTitles conserta registros gravados sem título, quando o resolvedor passa a responder")
    func backfillTitlesConsertaRegistros() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        persistence.appendPage([makeProduct(id: 1)], startingAt: 0, accountID: accountID) { _ in nil }
        #expect(persistence.search(matching: "argola", accountID: accountID, limit: 500).isEmpty)

        persistence.backfillTitles(resolver: { $0 == 1 ? "brinco argola" : nil }, accountID: accountID)

        #expect(persistence.search(matching: "argola", accountID: accountID, limit: 500).map(\.id) == [1])
    }

    @Test("search não vaza entre contas e respeita o fetchLimit")
    func searchNaoVazaERespeitaLimite() {
        let persistence = SwiftDataSmartPriceProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.appendPage((1...5).map { makeProduct(id: $0) }, startingAt: 0, accountID: accountA) { "produto \($0)" }
        persistence.appendPage([makeProduct(id: 99)], startingAt: 0, accountID: accountB) { "produto \($0)" }

        #expect(persistence.search(matching: "", accountID: accountA, limit: 3).count == 3)
        #expect(persistence.search(matching: "produto", accountID: accountB, limit: 500).map(\.id) == [99])
    }

    @Test("descarta registros existentes quando a versão de esquema salva está desatualizada")
    func descartaRegistrosComVersaoDesatualizada() {
        let container = makeContainer()
        let defaults = makeDefaults()
        let accountID = EnjoeiAccountID()
        let persistence = SwiftDataSmartPriceProductsPersistence(container: container, defaults: defaults)
        persistence.saveItems([makeProduct(id: 1)], accountID: accountID)
        defaults.set(0, forKey: "smartPrice.schemaVersion")

        let migratedPersistence = SwiftDataSmartPriceProductsPersistence(container: container, defaults: defaults)

        #expect(migratedPersistence.loadItems(accountID: accountID).isEmpty)
    }

    @Test("não descarta de novo quando a versão de esquema já está atualizada")
    func naoDescartaDeNovoQuandoVersaoJaAtualizada() {
        let container = makeContainer()
        let defaults = makeDefaults()
        let accountID = EnjoeiAccountID()
        let persistence = SwiftDataSmartPriceProductsPersistence(container: container, defaults: defaults)
        persistence.saveItems([makeProduct(id: 1)], accountID: accountID)

        let secondPersistence = SwiftDataSmartPriceProductsPersistence(container: container, defaults: defaults)

        #expect(secondPersistence.loadItems(accountID: accountID).map(\.id) == [1])
    }

    @Test("migra a lista salva pela versão antiga (UserDefaults) uma única vez, só da conta lida")
    func migraListaLegada() {
        let defaults = makeDefaults()
        let accountID = EnjoeiAccountID()
        let legacyItems = [makeProduct(id: 1), makeProduct(id: 2)]
        defaults.set(try! JSONEncoder().encode(legacyItems), forKey: "smartPrice.items.\(accountID)")
        let container = makeContainer()

        let persistence = SwiftDataSmartPriceProductsPersistence(container: container, defaults: defaults)

        #expect(persistence.loadItems(accountID: accountID) == legacyItems)
        #expect(defaults.object(forKey: "smartPrice.items.\(accountID)") == nil)

        let secondPersistence = SwiftDataSmartPriceProductsPersistence(container: container, defaults: defaults)
        #expect(secondPersistence.loadItems(accountID: accountID).count == 2)
    }
}
