import Foundation
import SwiftData
import Testing
@testable import MaryBottom

@Suite("container SwiftData por conta")
struct PerAccountModelContainerTests {
    private func makeProduct(id: Int) -> InactiveProduct {
        InactiveProduct(id: id, path: "produto-\(id)", title: "produto \(id)", price: nil, photoPublicID: nil, inactiveSince: nil)
    }

    @Test("contas diferentes recebem containers diferentes — nada gravado numa aparece na outra")
    func contasDiferentesRecebemContainersDiferentes() {
        let accountA = EnjoeiAccountID()
        let accountB = EnjoeiAccountID()
        defer {
            PerAccountModelContainer.destroy(for: accountA)
            PerAccountModelContainer.destroy(for: accountB)
        }

        SwiftDataInactiveProductsPersistence(accountID: accountA).saveItems([makeProduct(id: 1)])

        #expect(SwiftDataInactiveProductsPersistence(accountID: accountB).loadItems().isEmpty)
    }

    @Test("a mesma conta sempre devolve o mesmo container (cache), não cria um novo a cada chamada")
    func mesmaContaDevolveOMesmoContainerCacheado() {
        let accountID = EnjoeiAccountID()
        defer { PerAccountModelContainer.destroy(for: accountID) }

        let first = PerAccountModelContainer.shared(for: accountID)
        let second = PerAccountModelContainer.shared(for: accountID)

        let context = ModelContext(first)
        context.insert(InactiveProductRecord(sortIndex: 0, product: makeProduct(id: 1)))
        try? context.save()

        // Se fossem containers diferentes (arquivos diferentes), o segundo não veria o que o
        // primeiro gravou.
        let secondContext = ModelContext(second)
        let records = try? secondContext.fetch(FetchDescriptor<InactiveProductRecord>())
        #expect(records?.count == 1)
    }

    @Test("destroy apaga os dados da conta — uma persistência nova pra mesma conta não vê nada")
    func destroyApagaOsDadosDaConta() {
        let accountID = EnjoeiAccountID()
        let persistence = SwiftDataInactiveProductsPersistence(accountID: accountID)
        persistence.saveItems([makeProduct(id: 1)])
        #expect(persistence.loadItems().count == 1)

        PerAccountModelContainer.destroy(for: accountID)

        let freshPersistence = SwiftDataInactiveProductsPersistence(accountID: accountID)
        #expect(freshPersistence.loadItems().isEmpty)

        PerAccountModelContainer.destroy(for: accountID)
    }
}
