import Foundation
import Testing
@testable import MB_Admin

@Suite("ações em massa de publicados")
struct PublishedBulkActionTests {
    @Test("título da confirmação conta os produtos, no singular e no plural")
    func tituloDaConfirmacao() {
        #expect(PublishedBulkAction.delete.confirmationTitle(count: 3) == "apagar 3 produtos?")
        #expect(PublishedBulkAction.delete.confirmationTitle(count: 1) == "apagar 1 produto?")
        #expect(PublishedBulkAction.repost.confirmationTitle(count: 2) == "repostar 2 produtos?")
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
        #expect(PublishedBulkAction.repost.role == .standard)
        #expect(PublishedBulkAction.inactivate.role == .standard)
    }

    @Test("apagar avisa que é irreversível")
    func apagarAvisaQueEIrreversivel() {
        #expect(PublishedBulkAction.delete.confirmationMessage.hasPrefix("ação irreversível"))
    }
}
