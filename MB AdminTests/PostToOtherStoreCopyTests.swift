import Foundation
import Testing
@testable import MB_Admin

@Suite("textos de postar em outra loja")
struct PostToOtherStoreCopyTests {
    private func target(_ name: String, existing: Int = 0, possible: Int = 0, otherVersion: Int = 0) -> OtherStoreTarget {
        OtherStoreTarget(
            accountID: EnjoeiAccountID(),
            name: name,
            nickname: "nick",
            existingCount: existing,
            possibleCount: possible,
            otherVersionCount: otherVersion
        )
    }

    @Test("cabeçalho do menu de lojas conta os produtos só quando é mais de um")
    func cabecalhoDoMenu() {
        #expect(PostToOtherStoreCopy.menuTitle(productCount: 1) == "postar em")
        #expect(PostToOtherStoreCopy.menuTitle(productCount: 3) == "postar 3 em")
    }

    @Test("rótulos do item e do botão de confirmar")
    func rotulos() {
        #expect(PostToOtherStoreCopy.postLabel(storeName: "loja B") == "postar em loja B")
        #expect(PostToOtherStoreCopy.postingLabel(storeName: "loja B") == "postando em loja B…")
    }

    @Test("título da confirmação: este produto, ou a contagem")
    func tituloDaConfirmacao() {
        #expect(PostToOtherStoreCopy.confirmationTitle(productCount: 1, storeName: "loja B") == "postar este produto em loja B?")
        #expect(PostToOtherStoreCopy.confirmationTitle(productCount: 3, storeName: "loja B") == "postar 3 produtos em loja B?")
    }

    @Test("um produto: vira um anúncio novo e o daqui continua")
    func mensagemDeUmProduto() {
        let message = PostToOtherStoreCopy.confirmationMessage(productCount: 1, target: target("loja B"), pace: "1 a cada minuto")
        #expect(
            message == "vira um anúncio novo em loja B, com o mesmo título, descrição, preço e fotos, "
                + "e entra na fila de ações. o anúncio daqui continua como está."
        )
    }

    @Test("um produto que a última comparação achou lá (mesma foto): diz que vira repetido")
    func mensagemDeUmProdutoQueJaExiste() {
        let message = PostToOtherStoreCopy.confirmationMessage(productCount: 1, target: target("loja C", existing: 1), pace: "1 a cada minuto")
        #expect(
            message == "loja C já tem esse produto, pela última comparação (a mesma foto). "
                + "se postar, vira um anúncio repetido lá, com o mesmo título, descrição, preço e fotos."
        )
    }

    @Test("um produto que ficou pra revisar: diz que pode já existir")
    func mensagemDeUmProdutoQuePodeExistir() {
        let message = PostToOtherStoreCopy.confirmationMessage(productCount: 1, target: target("loja C", possible: 1), pace: "1 a cada minuto")
        #expect(
            message == "loja C pode já ter esse produto — a última comparação deixou um par pra revisar. "
                + "se postar, vira um anúncio novo lá, com o mesmo título, descrição, preço e fotos."
        )
    }

    @Test("vários: diz o ritmo da fila")
    func mensagemDeVarios() {
        let message = PostToOtherStoreCopy.confirmationMessage(productCount: 3, target: target("loja B"), pace: "1 a cada minuto")
        #expect(
            message == "cada um vira um anúncio novo em loja B, com título, descrição, preço e fotos, "
                + "e entra na fila de ações (1 a cada minuto). os anúncios daqui continuam como estão."
        )
    }

    @Test("vários com alguns já lá: avisa quantos antes, separando certo de possível")
    func mensagemDeVariosComRisco() {
        let one = PostToOtherStoreCopy.confirmationMessage(productCount: 3, target: target("loja C", existing: 1), pace: "1 a cada 30s")
        #expect(one.hasPrefix("1 deles já existe em loja C, pela última comparação. cada um vira"))
        #expect(one.contains("(1 a cada 30s)"))

        let possible = PostToOtherStoreCopy.confirmationMessage(productCount: 3, target: target("loja C", possible: 2), pace: "1 a cada minuto")
        #expect(possible.hasPrefix("2 deles podem existir em loja C, pela última comparação."))

        let both = PostToOtherStoreCopy.confirmationMessage(productCount: 3, target: target("loja C", existing: 2, possible: 1), pace: "1 a cada minuto")
        #expect(both.hasPrefix("2 deles já existem em loja C e 1 pode existir, pela última comparação."))
    }

    @Test("lá tem o produto em outra versão: avisa, sem tratar como repetido")
    func mensagemDeOutraVersao() {
        let one = PostToOtherStoreCopy.confirmationMessage(productCount: 1, target: target("loja C", otherVersion: 1), pace: "1 a cada minuto")
        #expect(one.hasPrefix("loja C tem esse produto em outra versão (a mesma foto, com outro tamanho, banho, cor ou medida), mas não nesta"))
        #expect(!one.contains("repetido"))

        let many = PostToOtherStoreCopy.confirmationMessage(productCount: 3, target: target("loja C", otherVersion: 2), pace: "1 a cada minuto")
        #expect(many.hasPrefix("loja C tem 2 deles em outra versão, mas não nesta, pela última comparação. cada um vira"))

        // Risco de duplicar vem primeiro; a outra versão não muda o aviso.
        let risky = PostToOtherStoreCopy.confirmationMessage(productCount: 3, target: target("loja C", existing: 1, otherVersion: 1), pace: "1 a cada minuto")
        #expect(risky.hasPrefix("1 deles já existe em loja C, pela última comparação."))
    }
}
