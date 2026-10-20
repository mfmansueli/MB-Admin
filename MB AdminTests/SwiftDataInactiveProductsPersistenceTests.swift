import Foundation
import SwiftData
import Testing
@testable import MB_Admin

@Suite("persistência da lista de produtos inativos em SwiftData")
struct SwiftDataInactiveProductsPersistenceTests {
    /// Container em memória, isolado por teste — sem isso, os testes gravariam no banco de
    /// verdade usado pelo app.
    private func makeContainer() -> ModelContainer {
        let schema = Schema([InactiveProductRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }

    /// Suite efêmera própria por teste, pra a migração da chave legada não sujar (nem depender
    /// de) o `UserDefaults.standard` da máquina rodando os testes.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SwiftDataInactiveProductsPersistenceTests.\(UUID().uuidString)")!
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
        let persistence = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        #expect(persistence.loadItems().isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, na mesma ordem")
    func salvaELeDeVolta() {
        let persistence = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        let items = [makeProduct(id: 1), makeProduct(id: 2)]

        persistence.saveItems(items)

        #expect(persistence.loadItems() == items)
    }

    @Test("salvar de novo substitui a lista anterior, não acumula")
    func salvarDeNovoSubstitui() {
        let persistence = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([makeProduct(id: 1), makeProduct(id: 2)])

        persistence.saveItems([makeProduct(id: 3)])

        #expect(persistence.loadItems().map(\.id) == [3])
    }

    @Test("duas contas com containers separados não compartilham nada — mesmo raciocínio de PerAccountModelContainer")
    func duasContasComContainersSeparadosNaoCompartilhamNada() {
        let persistenceA = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        let persistenceB = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistenceA.saveItems([makeProduct(id: 1)])

        #expect(persistenceB.loadItems().isEmpty)
    }

    @Test("clearItems apaga tudo")
    func clearItemsApagaTudo() {
        let persistence = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([makeProduct(id: 1)])

        persistence.clearItems()

        #expect(persistence.loadItems().isEmpty)
    }

    @Test("appendPage acrescenta sem apagar o que já tinha, respeitando o offset")
    func appendPageAcrescentaRespeitandoOffset() {
        let persistence = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())

        persistence.appendPage([makeProduct(id: 1), makeProduct(id: 2)], startingAt: 0)
        persistence.appendPage([makeProduct(id: 3)], startingAt: 2)

        #expect(persistence.loadItems().map(\.id) == [1, 2, 3])
    }

    @Test("search encontra por título, sem diferenciar maiúsculas/minúsculas")
    func searchEncontraPorTitulo() {
        let persistence = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems([
            InactiveProduct(id: 1, path: "p1", title: "Brinco Argola", price: 100, photoPublicID: nil, inactiveSince: nil),
            InactiveProduct(id: 2, path: "p2", title: "colar prata", price: 100, photoPublicID: nil, inactiveSince: nil)
        ])

        #expect(persistence.search(matching: "argola", limit: 500).map(\.id) == [1])
        #expect(persistence.search(matching: "PRATA", limit: 500).map(\.id) == [2])
        #expect(persistence.search(matching: "inexistente", limit: 500).isEmpty)
    }

    @Test("search respeita o fetchLimit")
    func searchRespeitaOFetchLimit() {
        let persistence = SwiftDataInactiveProductsPersistence(accountID: EnjoeiAccountID(), container: makeContainer(), defaults: makeDefaults())
        persistence.saveItems((1...5).map { makeProduct(id: $0) })

        #expect(persistence.search(matching: "", limit: 3).count == 3)
    }

    @Test("descarta registros existentes quando a versão de esquema salva está desatualizada")
    func descartaRegistrosComVersaoDesatualizada() {
        let accountID = EnjoeiAccountID()
        let container = makeContainer()
        let defaults = makeDefaults()
        let persistence = SwiftDataInactiveProductsPersistence(accountID: accountID, container: container, defaults: defaults)
        persistence.saveItems([makeProduct(id: 1)])
        // Força a versão salva de volta pra trás — simula quem tinha registros de antes dessa
        // migração de esquema existir (`payload` codificado virando colunas nativas).
        defaults.set(0, forKey: "inactive.schemaVersion.\(accountID)")

        let migratedPersistence = SwiftDataInactiveProductsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(migratedPersistence.loadItems().isEmpty)
    }

    @Test("não descarta de novo quando a versão de esquema já está atualizada")
    func naoDescartaDeNovoQuandoVersaoJaAtualizada() {
        let accountID = EnjoeiAccountID()
        let container = makeContainer()
        let defaults = makeDefaults()
        let persistence = SwiftDataInactiveProductsPersistence(accountID: accountID, container: container, defaults: defaults)
        persistence.saveItems([makeProduct(id: 1)])

        let secondPersistence = SwiftDataInactiveProductsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(secondPersistence.loadItems().map(\.id) == [1])
    }

    @Test("migra a lista salva pela versão antiga (UserDefaults) uma única vez")
    func migraListaLegada() {
        let accountID = EnjoeiAccountID()
        let defaults = makeDefaults()
        let legacyItems = [makeProduct(id: 1), makeProduct(id: 2)]
        defaults.set(try! JSONEncoder().encode(legacyItems), forKey: "inactive.items.\(accountID)")
        let container = makeContainer()

        let persistence = SwiftDataInactiveProductsPersistence(accountID: accountID, container: container, defaults: defaults)

        #expect(persistence.loadItems() == legacyItems)
        #expect(defaults.object(forKey: "inactive.items.\(accountID)") == nil)

        // Reler com o mesmo container não duplica os itens já migrados: a chave legada já não
        // existe mais pra segunda leitura encontrar.
        let secondPersistence = SwiftDataInactiveProductsPersistence(accountID: accountID, container: container, defaults: defaults)
        #expect(secondPersistence.loadItems().count == 2)
    }
}
