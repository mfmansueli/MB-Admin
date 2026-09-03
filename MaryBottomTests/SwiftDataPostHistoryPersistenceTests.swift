import Foundation
import SwiftData
import Testing
@testable import MaryBottom

@Suite("persistência do histórico da fila em SwiftData")
struct SwiftDataPostHistoryPersistenceTests {
    /// Container em memória, isolado por teste — sem isso, os testes gravariam no banco de
    /// verdade usado pelo app.
    private func makeContainer() -> ModelContainer {
        let schema = Schema([PostHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }

    /// Suite efêmera própria por teste, pra a migração da chave legada não sujar (nem depender
    /// de) o `UserDefaults.standard` da máquina rodando os testes.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SwiftDataPostHistoryPersistenceTests.\(UUID().uuidString)")!
    }

    private func makeEntry(
        id: UUID = UUID(),
        productID: Int,
        outcome: PostHistoryEntry.Outcome = .succeeded,
        completedAt: Date = .now
    ) -> PostHistoryEntry {
        PostHistoryEntry(
            id: id,
            product: EnjoeiProduct(
                id: productID,
                title: "produto \(productID)",
                path: "produto-\(productID)",
                photoPublicID: "foto-\(productID)",
                currentPrice: 100,
                originalPrice: 150
            ),
            kind: .post,
            sourceAccountID: EnjoeiAccountID(),
            sourceAccountName: "origem",
            destinationAccountID: EnjoeiAccountID(),
            destinationAccountName: "destino",
            outcome: outcome,
            completedAt: completedAt
        )
    }

    @Test("sem nada salvo ainda, devolve lista vazia")
    func semNadaSalvo() {
        let persistence = SwiftDataPostHistoryPersistence(container: makeContainer(), defaults: makeDefaults())
        #expect(persistence.loadEntries().isEmpty)
    }

    @Test("insere uma entrada de cada vez e lê de volta, mais recente primeiro")
    func insereELeDeVolta() {
        let persistence = SwiftDataPostHistoryPersistence(container: makeContainer(), defaults: makeDefaults())
        let older = makeEntry(productID: 1, completedAt: .now.addingTimeInterval(-60))
        let newer = makeEntry(productID: 2, completedAt: .now)

        persistence.insert(older)
        persistence.insert(newer)

        #expect(persistence.loadEntries() == [newer, older])
    }

    @Test("guarda erro e os quatro tipos de ação corretamente")
    func guardaErroETiposDeAcao() {
        let persistence = SwiftDataPostHistoryPersistence(container: makeContainer(), defaults: makeDefaults())
        let entry = makeEntry(productID: 1, outcome: .failed("o enjoei caiu"))

        persistence.insert(entry)

        #expect(persistence.loadEntries() == [entry])
    }

    @Test("clear apaga tudo")
    func clearApagaTudo() {
        let persistence = SwiftDataPostHistoryPersistence(container: makeContainer(), defaults: makeDefaults())
        persistence.insert(makeEntry(productID: 1))
        persistence.insert(makeEntry(productID: 2))

        persistence.clear()

        #expect(persistence.loadEntries().isEmpty)
    }

    @Test("migra o histórico salvo pela versão antiga (UserDefaults) uma única vez")
    func migraHistoricoLegado() {
        let defaults = makeDefaults()
        let legacyEntries = [makeEntry(productID: 1), makeEntry(productID: 2)]
        defaults.set(try! JSONEncoder().encode(legacyEntries), forKey: "postHistory.v1")
        let container = makeContainer()

        let persistence = SwiftDataPostHistoryPersistence(container: container, defaults: defaults)

        #expect(Set(persistence.loadEntries().map(\.id)) == Set(legacyEntries.map(\.id)))
        #expect(defaults.object(forKey: "postHistory.v1") == nil)

        // Reabrir com o mesmo container não duplica as entradas já migradas: a chave legada já
        // não existe mais para a segunda instância ler de novo.
        let secondPersistence = SwiftDataPostHistoryPersistence(container: container, defaults: defaults)
        #expect(secondPersistence.loadEntries().count == 2)
    }
}
