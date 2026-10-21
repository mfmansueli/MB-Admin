import Foundation
import Testing
@testable import MB_Admin

@Suite("diagnóstico completo de uma ação que falhou")
struct MegaphoneFailureDetailTests {
    /// De propósito sem `CustomStringConvertible`: `String(describing:)` cai pro dump padrão do
    /// tipo (inclui o nome), que é exatamente o que `technicalDescription` deve capturar pra
    /// qualquer `Error` que não seja `EnjoeiError`.
    private struct GenericError: Error {}

    @Test("erro EnjoeiError.http extrai status e mensagem do servidor")
    func erroHTTPExtraiStatusEMensagem() {
        let detail = MegaphoneFailureDetail(action: .delete, error: EnjoeiError.http(status: 503, message: "fora do ar"))

        #expect(detail.httpStatus == 503)
        #expect(detail.serverMessage == "fora do ar")
        #expect(detail.technicalDescription == EnjoeiError.http(status: 503, message: "fora do ar").diagnosticDescription)
    }

    @Test("erro EnjoeiError que não é .http não tem status nem mensagem do servidor")
    func erroNaoHTTPSemStatusOuMensagem() {
        let detail = MegaphoneFailureDetail(action: .megaphone, error: EnjoeiError.notAuthenticated)

        #expect(detail.httpStatus == nil)
        #expect(detail.serverMessage == nil)
        #expect(detail.technicalDescription == "EnjoeiError.notAuthenticated")
    }

    @Test("erro que não é EnjoeiError cai pra descrição genérica, sem status nem mensagem")
    func erroGenericoCaiParaDescricaoBruta() {
        let detail = MegaphoneFailureDetail(action: .activate, error: GenericError())

        #expect(detail.httpStatus == nil)
        #expect(detail.serverMessage == nil)
        #expect(detail.technicalDescription.contains("GenericError"))
    }

    @Test("falha sintética (sem Error real por trás) repete a mensagem na descrição técnica")
    func falhaSinteticaRepeteAMensagem() {
        let detail = MegaphoneFailureDetail(action: .post, syntheticMessage: "conta não está mais logada")

        #expect(detail.httpStatus == nil)
        #expect(detail.serverMessage == nil)
        #expect(detail.technicalDescription == "conta não está mais logada")
    }

    @Test("Action.init(kind:) mapeia cada PostQueueItem.Kind pra ação correspondente")
    func actionInitMapeiaKind() {
        #expect(MegaphoneFailureDetail.Action(kind: .post) == .post)
        #expect(MegaphoneFailureDetail.Action(kind: .delete) == .delete)
        #expect(MegaphoneFailureDetail.Action(kind: .inactivate) == .inactivate)
        #expect(MegaphoneFailureDetail.Action(kind: .activate) == .activate)
    }

    @Test("shareText reúne ação, status HTTP e resposta do servidor quando presentes")
    func shareTextReuneCampos() {
        let detail = MegaphoneFailureDetail(action: .delete, error: EnjoeiError.http(status: 500, message: "o enjoei caiu"))

        let text = detail.shareText

        #expect(text.contains("ação: apagar"))
        #expect(text.contains("status HTTP: 500"))
        #expect(text.contains("resposta do servidor: o enjoei caiu"))
        #expect(text.contains("descrição técnica:"))
    }

    @Test("cada ação diz em vermelho o que deixou de acontecer")
    func fraseDaFalhaPorAcao() {
        #expect(MegaphoneFailureDetail.Action.megaphone.failureHeadline == "megafone não foi")
        #expect(MegaphoneFailureDetail.Action.applyDiscount.failureHeadline == "desconto não foi aplicado")
        #expect(MegaphoneFailureDetail.Action.post.failureHeadline == "não deu pra postar")
        #expect(MegaphoneFailureDetail.Action.delete.failureHeadline == "não deu pra apagar")
        #expect(MegaphoneFailureDetail.Action.inactivate.failureHeadline == "não deu pra inativar")
        #expect(MegaphoneFailureDetail.Action.activate.failureHeadline == "não deu pra ativar")
    }

    @Test("diagnóstico técnico na ordem da tela, com status HTTP e resposta quando o erro traz")
    func linhasDoDiagnosticoComHTTP() {
        let detail = MegaphoneFailureDetail(action: .megaphone, error: EnjoeiError.http(status: 504, message: "Gateway Time-out"))

        let rows = detail.diagnosticRows

        #expect(rows.map(\.label) == ["ação", "hora", "status HTTP", "resposta", "descrição"])
        #expect(rows[0].value == "megafonar")
        #expect(rows[2].value == "504")
        #expect(rows[3].value == "Gateway Time-out")
        #expect(rows[4].value == detail.technicalDescription)
    }

    @Test("sem status HTTP nem resposta, o diagnóstico fica só com ação, hora e descrição")
    func linhasDoDiagnosticoSemHTTP() {
        let detail = MegaphoneFailureDetail(action: .post, syntheticMessage: "conta não está mais logada")

        #expect(detail.diagnosticRows.map(\.label) == ["ação", "hora", "descrição"])
    }

    @Test("shareText omite status HTTP e resposta do servidor quando não existem")
    func shareTextOmiteCamposAusentes() {
        let detail = MegaphoneFailureDetail(action: .megaphone, error: EnjoeiError.notAuthenticated)

        let text = detail.shareText

        #expect(!text.contains("status HTTP"))
        #expect(!text.contains("resposta do servidor"))
    }
}
