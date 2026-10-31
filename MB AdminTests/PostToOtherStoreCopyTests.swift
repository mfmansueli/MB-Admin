import Foundation
import Testing
@testable import MB_Admin

@Suite("textos de postar em outra loja")
struct PostToOtherStoreCopyTests {
    private func target(_ name: String, duplicates: Int = 0, percent: Int? = nil) -> OtherStoreTarget {
        OtherStoreTarget(
            accountID: EnjoeiAccountID(),
            name: name,
            nickname: "nick",
            possibleDuplicateCount: duplicates,
            highestSimilarityPercent: percent
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

    @Test("um produto que a última comparação achou lá: começa pelo risco")
    func mensagemDeUmProdutoComRisco() {
        let message = PostToOtherStoreCopy.confirmationMessage(
            productCount: 1,
            target: target("loja C", duplicates: 1, percent: 82),
            pace: "1 a cada minuto"
        )
        #expect(
            message == "loja C pode já ter esse produto (82% parecido). "
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

    @Test("vários com alguns já lá: avisa quantos antes")
    func mensagemDeVariosComRisco() {
        let one = PostToOtherStoreCopy.confirmationMessage(
            productCount: 3,
            target: target("loja C", duplicates: 1, percent: 82),
            pace: "1 a cada 30s"
        )
        #expect(one.hasPrefix("1 deles pode já existir em loja C, pela última comparação. cada um vira"))
        #expect(one.contains("(1 a cada 30s)"))

        let two = PostToOtherStoreCopy.confirmationMessage(
            productCount: 3,
            target: target("loja C", duplicates: 2, percent: 90),
            pace: "1 a cada minuto"
        )
        #expect(two.hasPrefix("2 deles podem já existir em loja C"))
    }
}
