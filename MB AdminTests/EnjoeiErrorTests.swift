import Foundation
import Testing
@testable import MB_Admin

@Suite("detecção de erros do Enjoei a partir do corpo da resposta")
struct EnjoeiErrorTests {
    @Test("reconhece persisted query desconhecida, ignorando maiúsculas/minúsculas")
    func reconhecePersistedQueryDesconhecida() {
        let body = Data(#"{"errors":[{"message":"PersistedQueryNotFound"}]}"#.utf8)
        #expect(EnjoeiError.isStalePersistedQuery(in: body))
    }

    @Test("não confunde outro erro GraphQL qualquer com persisted query desatualizada")
    func naoConfundeOutroErro() {
        let body = Data(#"{"errors":[{"message":"seller_id inválido"}]}"#.utf8)
        #expect(!EnjoeiError.isStalePersistedQuery(in: body))
    }

    @Test("resposta sem chave errors não é confundida com persisted query desatualizada")
    func semChaveErrors() {
        let body = Data(#"{"data":{"seller":null}}"#.utf8)
        #expect(!EnjoeiError.isStalePersistedQuery(in: body))
    }

    @Test("JSON inválido não é confundido com persisted query desatualizada")
    func jsonInvalido() {
        let body = Data("não é json".utf8)
        #expect(!EnjoeiError.isStalePersistedQuery(in: body))
    }
}
