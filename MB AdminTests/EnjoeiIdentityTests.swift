import Foundation
import Testing
@testable import MB_Admin

@Suite("identificação de quem está logado na página")
struct EnjoeiIdentityTests {
    @Test("lê apelido, id e token do resultado do script")
    func lePaginaLogada() {
        let identity = EnjoeiIdentity(javaScriptResult: [
            "nickname": "antonia-40d0aa",
            "id": NSNumber(value: 28714888),
            "csrf": "token-abc",
            "currentUserStatus": NSNumber(value: 200)
        ])

        #expect(identity.isIdentified)
        #expect(identity.nickname == "antonia-40d0aa")
        #expect(identity.id == 28714888)
        #expect(identity.csrfToken == "token-abc")
    }

    @Test("página de visitante não identifica ninguém, mas explica o porquê")
    func paginaDeVisitante() {
        let identity = EnjoeiIdentity(javaScriptResult: [
            "csrf": "",
            "currentUserStatus": NSNumber(value: 401),
            "myStoreStatus": NSNumber(value: 200)
        ])

        #expect(identity.isIdentified == false)
        #expect(identity.csrfToken == nil)
        #expect(identity.diagnosticSummary == "current_user: 401, minha-loja: 200")
    }

    @Test("resultado estranho do script não quebra o app")
    func resultadoInesperado() {
        #expect(EnjoeiIdentity(javaScriptResult: nil).isIdentified == false)
        #expect(EnjoeiIdentity(javaScriptResult: "oi").nickname == nil)
    }
}
