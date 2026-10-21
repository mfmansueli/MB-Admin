import Foundation
import Testing
@testable import MB_Admin

@Suite("ações em massa da aba inativos")
struct InactiveBulkActionTests {
    @Test("repostar, ativar e apagar, nessa ordem na barra")
    func ordemDaBarra() {
        #expect(InactiveBulkAction.allCases.map(\.label) == ["repostar", "ativar", "apagar"])
    }

    @Test("só apagar é destrutivo — vermelho na barra e no alerta")
    func soApagarEhDestrutivo() {
        #expect(InactiveBulkAction.delete.isDestructive)
        #expect(InactiveBulkAction.delete.role == .destructive)
        #expect(!InactiveBulkAction.repost.isDestructive)
        #expect(InactiveBulkAction.activate.role == .standard)
    }

    @Test("o título do alerta conta os produtos, no singular e no plural")
    func tituloDoAlerta() {
        #expect(InactiveBulkAction.repost.confirmationTitle(count: 1) == "repostar 1 produto?")
        #expect(InactiveBulkAction.activate.confirmationTitle(count: 3) == "ativar 3 produtos de novo?")
        #expect(InactiveBulkAction.delete.confirmationTitle(count: 2) == "apagar 2 produtos?")
    }

    @Test("apagar avisa que é irreversível")
    func apagarAvisaIrreversivel() {
        #expect(InactiveBulkAction.delete.confirmationMessage.hasPrefix("ação irreversível"))
    }
}
