import Foundation
import Testing
@testable import MB_Admin

@Suite("confirmação de apagar produto da loja")
struct PermanentDeleteCopyTests {
    @Test("o título alerta e conta os produtos, no singular e no plural")
    func titulo() {
        #expect(PermanentDeleteCopy.title(productCount: 1) == "⚠️ apagar este produto da loja para sempre?")
        #expect(PermanentDeleteCopy.title(productCount: 8) == "⚠️ apagar 8 produtos da loja para sempre?")
    }

    @Test("a mensagem diz que some de vez na raiz da loja, não só da fila")
    func mensagem() {
        for count in [1, 8] {
            let message = PermanentDeleteCopy.message(productCount: count)
            #expect(message.hasPrefix("atenção:"))
            #expect(message.contains("excluído") || message.contains("excluídos"))
            #expect(message.contains("permanentemente na raiz da sua loja no enjoei"))
            #expect(message.contains("não é só tirar do app ou da fila"))
            #expect(message.contains("não tem como recuperar"))
        }
        #expect(PermanentDeleteCopy.message(productCount: 8).contains("os 8 anúncios"))
    }

    @Test("o botão de confirmar não deixa dúvida")
    func botao() {
        #expect(PermanentDeleteCopy.confirmButtonLabel == "apagar permanentemente")
    }
}
