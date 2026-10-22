import Foundation
import Testing
@testable import MB_Admin

@Suite("filtro de publicados")
struct AccountProductFilterTests {
    @Test("nomes das cápsulas, na ordem da fileira")
    func nomesDasCapsulas() {
        #expect(AccountProductFilter.allCases.map(\.label) == ["todos os anúncios", "só os que pedem desconto"])
    }

    @Test("chave por conta continua a mesma — trocar perderia a escolha já guardada")
    func chaveGuardadaPorConta() throws {
        let accountID = try #require(UUID(uuidString: "DE300000-0000-0000-0000-00000000000A"))
        #expect(AccountProductFilter.storageKey(for: accountID) == "accountDetail.filter.\(accountID)")
    }

    @Test("o raw value guardado por conta continua o mesmo")
    func rawValueGuardado() {
        #expect(AccountProductFilter(rawValue: "all") == .all)
        #expect(AccountProductFilter(rawValue: "discountOnly") == .discountOnly)
    }
}
