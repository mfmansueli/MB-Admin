import Foundation
import Testing
@testable import MB_Admin

@Suite("ações em massa da aba inativos")
struct InactiveBulkActionTests {
    @Test("repostar e apagar, nessa ordem na barra — sem ativar")
    func ordemDaBarra() {
        #expect(InactiveBulkAction.allCases.map(\.label) == ["repostar", "apagar"])
        #expect(!InactiveBulkAction.allCases.map(\.queueKind).contains(.activate))
    }

    @Test("só apagar é destrutivo — vermelho na barra e no alerta")
    func soApagarEhDestrutivo() {
        #expect(InactiveBulkAction.delete.isDestructive)
        #expect(InactiveBulkAction.delete.role == .destructive)
        #expect(!InactiveBulkAction.repost.isDestructive)
        #expect(InactiveBulkAction.repost.role == .standard)
    }

    @Test("o título do alerta conta os produtos, no singular e no plural")
    func tituloDoAlerta() {
        #expect(InactiveBulkAction.repost.confirmationTitle(count: 1) == "repostar 1 produto?")
        #expect(InactiveBulkAction.repost.confirmationTitle(count: 3) == "repostar 3 produtos?")
        #expect(InactiveBulkAction.delete.confirmationTitle(count: 2) == "⚠️ apagar 2 produtos da loja para sempre?")
    }

    @Test("apagar usa a confirmação alarmante de excluir da loja de vez")
    func apagarUsaAConfirmacaoAlarmante() {
        #expect(InactiveBulkAction.delete.confirmationMessage(count: 2) == PermanentDeleteCopy.message(productCount: 2))
        #expect(InactiveBulkAction.delete.confirmationButtonLabel == "apagar permanentemente")
    }

    @Test("cada ação vira na fila o tipo certo — repostar é uma postagem na mesma loja")
    func tipoNaFila() {
        #expect(InactiveBulkAction.repost.queueKind == .post)
        #expect(InactiveBulkAction.delete.queueKind == .delete)
    }
}
