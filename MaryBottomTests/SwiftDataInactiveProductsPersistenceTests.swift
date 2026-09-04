import Foundation
import SwiftData
import Testing
@testable import MaryBottom

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
        let persistence = SwiftDataInactiveProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        #expect(persistence.loadItems(accountID: EnjoeiAccountID()).isEmpty)
    }

    @Test("guarda e lê de volta a lista inteira, na mesma ordem")
    func salvaELeDeVolta() {
        let persistence = SwiftDataInactiveProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        let items = [makeProduct(id: 1), makeProduct(id: 2)]

        persistence.saveItems(items, accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID) == items)
    }

    @Test("salvar de novo substitui a lista anterior da conta, não acumula")
    func salvarDeNovoSubstitui() {
        let persistence = SwiftDataInactiveProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountID = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1), makeProduct(id: 2)], accountID: accountID)

        persistence.saveItems([makeProduct(id: 3)], accountID: accountID)

        #expect(persistence.loadItems(accountID: accountID).map(\.id) == [3])
    }

    @Test("cada conta tem seus próprios registros, sem vazar pra outra")
    func registrosSeparadosPorConta() {
        let persistence = SwiftDataInactiveProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1)], accountID: accountA)

        #expect(persistence.loadItems(accountID: accountB).isEmpty)
    }

    @Test("clearItems apaga só a lista da conta pedida")
    func clearItemsApagaSoAConta() {
        let persistence = SwiftDataInactiveProductsPersistence(container: makeContainer(), defaults: makeDefaults())
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        persistence.saveItems([makeProduct(id: 1)], accountID: accountA)
        persistence.saveItems([makeProduct(id: 2)], accountID: accountB)

        persistence.clearItems(accountID: accountA)

        #expect(persistence.loadItems(accountID: accountA).isEmpty)
        #expect(persistence.loadItems(accountID: accountB).map(\.id) == [2])
    }

    @Test("migra a lista salva pela versão antiga (UserDefaults) uma única vez, só da conta lida")
    func migraListaLegada() {
        let defaults = makeDefaults()
        let accountID = EnjoeiAccountID()
        let legacyItems = [makeProduct(id: 1), makeProduct(id: 2)]
        defaults.set(try! JSONEncoder().encode(legacyItems), forKey: "inactive.items.\(accountID)")
        let container = makeContainer()

        let persistence = SwiftDataInactiveProductsPersistence(container: container, defaults: defaults)

        #expect(persistence.loadItems(accountID: accountID) == legacyItems)
        #expect(defaults.object(forKey: "inactive.items.\(accountID)") == nil)

        // Reler com o mesmo container não duplica os itens já migrados: a chave legada já não
        // existe mais pra segunda leitura encontrar.
        let secondPersistence = SwiftDataInactiveProductsPersistence(container: container, defaults: defaults)
        #expect(secondPersistence.loadItems(accountID: accountID).count == 2)
    }
}
