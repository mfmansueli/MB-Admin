import Foundation
import Testing
@testable import MB_Admin

@Suite("ações em massa de publicados")
struct PublishedBulkActionTests {
    @Test("título da confirmação conta os produtos, no singular e no plural")
    func tituloDaConfirmacao() {
        #expect(PublishedBulkAction.delete.confirmationTitle(count: 3) == "⚠️ apagar 3 produtos da loja para sempre?")
        #expect(PublishedBulkAction.delete.confirmationTitle(count: 1) == "⚠️ apagar este produto da loja para sempre?")
        #expect(PublishedBulkAction.inactivate.confirmationTitle(count: 1) == "inativar 1 produto?")
        #expect(PublishedBulkAction.applyDiscount.confirmationTitle(count: 4) == "aplicar desconto e megafonar 4 produtos?")
    }

    @Test("só apagar é destrutivo")
    func soApagarEDestrutivo() {
        #expect(PublishedBulkAction.allCases.filter(\.isDestructive) == [.delete])
    }

    @Test("cor de cada ação na barra: desconto pede decisão, apagar é destrutivo, o resto é comum")
    func papelDeCadaAcao() {
        #expect(PublishedBulkAction.applyDiscount.role == .decision)
        #expect(PublishedBulkAction.delete.role == .destructive)
        #expect(PublishedBulkAction.inactivate.role == .standard)
        #expect(PublishedBulkAction.postToOtherStore.role == .standard)
    }

    @Test("repostar fica fora da seleção de publicados — só no menu de cada produto")
    func semRepostarNaSelecao() {
        #expect(PublishedBulkAction.allCases == [.applyDiscount, .postToOtherStore, .inactivate, .delete])
        #expect(!PublishedBulkAction.allCases.map(\.label).contains("repostar"))
        // A aba "inativos" continua com o dela.
        #expect(InactiveBulkAction.allCases.contains(.repost))
    }

    @Test("postar em vem logo antes de inativar, abre o menu das lojas e encurta no iPhone")
    func postarEmOutraLoja() {
        let actions = PublishedBulkAction.allCases
        let index = actions.firstIndex(of: .postToOtherStore)
        #expect(index == actions.firstIndex(of: .inactivate).map { $0 - 1 })
        #expect(actions.filter(\.opensMenu) == [.postToOtherStore])
        #expect(PublishedBulkAction.postToOtherStore.label == "postar em")
        #expect(PublishedBulkAction.postToOtherStore.compactLabel == "postar")
        #expect(PublishedBulkAction.postToOtherStore.systemImage == "paperplane")
        #expect(PublishedBulkAction.inactivate.compactLabel == "inativar")
        #expect(!PublishedBulkAction.postToOtherStore.isDestructive)
    }

    @Test("cada ação vira na fila o tipo certo — desconto não passa pela fila")
    func tipoNaFila() {
        #expect(PublishedBulkAction.applyDiscount.queueKind == nil)
        #expect(PublishedBulkAction.postToOtherStore.queueKind == .post)
        #expect(PublishedBulkAction.inactivate.queueKind == .inactivate)
        #expect(PublishedBulkAction.delete.queueKind == .delete)
    }

    @Test("apagar usa a confirmação alarmante de excluir da loja de vez")
    func apagarUsaAConfirmacaoAlarmante() {
        #expect(PublishedBulkAction.delete.confirmationMessage(count: 3) == PermanentDeleteCopy.message(productCount: 3))
        #expect(PublishedBulkAction.delete.confirmationButtonLabel == "apagar permanentemente")
        // As outras não mudam com a quantidade.
        #expect(PublishedBulkAction.inactivate.confirmationMessage(count: 1) == PublishedBulkAction.inactivate.confirmationMessage(count: 5))
    }
}
