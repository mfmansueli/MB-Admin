import Foundation
import Testing
@testable import MB_Admin

@Suite("resposta do megafone feito na webview")
struct MegaphoneWebResponseTests {
    @Test("2xx é sucesso")
    func sucesso() {
        #expect(MegaphoneWebResponse(status: 200).failure == nil)
        #expect(MegaphoneWebResponse(status: 201).failure == nil)
    }

    @Test("mostra a mensagem que o enjoei mandou")
    func erroComMensagemDoServidor() {
        let response = MegaphoneWebResponse(
            status: 429,
            body: #"{"error":"você já megafonou demais hoje"}"#
        )

        #expect(response.failure == .http(status: 429, message: "você já megafonou demais hoje"))
    }

    @Test("401 é sessão caída e 422 é token recusado")
    func statusEspeciais() {
        #expect(MegaphoneWebResponse(status: 401).failure == .notAuthenticated)
        #expect(MegaphoneWebResponse(status: 422).failure == .invalidCSRFToken)
        #expect(MegaphoneWebResponse(status: 422).failure?.isCSRFRejection == true)
    }

    @Test("lê o dicionário devolvido pelo javascript")
    func leResultadoDoJavaScript() {
        let response = MegaphoneWebResponse(javaScriptResult: [
            "status": NSNumber(value: 200),
            "body": "{}"
        ])

        #expect(response.status == 200)
        #expect(response.failure == nil)
    }
}
