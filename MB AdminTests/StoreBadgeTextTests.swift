import Foundation
import Testing
@testable import MB_Admin

@Suite("etiqueta da loja no topo do detalhe da conta")
struct StoreBadgeTextTests {
    @Test("o nome da conta vira \"loja <nome>\"")
    func nomeDaLoja() {
        #expect(StoreBadgeText.storeName("Mary") == "loja Mary")
        #expect(StoreBadgeText.storeName("Antônia") == "loja Antônia")
        #expect(StoreBadgeText.storeName("  Iago ") == "loja Iago")
    }

    @Test("nome que já começa com \"loja\" não ganha outro na frente")
    func semLojaDobrado() {
        #expect(StoreBadgeText.storeName("loja B") == "loja B")
        #expect(StoreBadgeText.storeName("Loja da Mary") == "Loja da Mary")
        #expect(StoreBadgeText.storeName("LOJA") == "LOJA")
        // Só a palavra inteira — "lojinha" é outro nome.
        #expect(StoreBadgeText.storeName("lojinha") == "loja lojinha")
    }

    @Test("total soma publicados e inativos; sem nenhum dos dois carregado, não tem total")
    func total() {
        #expect(StoreBadgeText.totalProducts(published: 1502, inactive: 340) == 1842)
        #expect(StoreBadgeText.totalProducts(published: 1502, inactive: nil) == 1502)
        #expect(StoreBadgeText.totalProducts(published: nil, inactive: 8) == 8)
        #expect(StoreBadgeText.totalProducts(published: 0, inactive: 0) == 0)
        #expect(StoreBadgeText.totalProducts(published: nil, inactive: nil) == nil)
    }

    @Test("quantidade no singular e no plural")
    func quantidade() {
        #expect(StoreBadgeText.productCount(1) == "1 produto")
        #expect(StoreBadgeText.productCount(68) == "68 produtos")
        #expect(StoreBadgeText.productCount(1842) == "\(1842.formatted()) produtos")
    }

    @Test("VoiceOver lê a loja, o total e de onde ele vem")
    func acessibilidade() {
        #expect(
            StoreBadgeText.accessibilityLabel(name: "Mary", published: 60, inactive: 8)
                == "loja Mary, 68 produtos: 60 publicados e 8 inativos"
        )
        #expect(
            StoreBadgeText.accessibilityLabel(name: "Iago", published: 1, inactive: 1)
                == "loja Iago, 2 produtos: 1 publicado e 1 inativo"
        )
        #expect(
            StoreBadgeText.accessibilityLabel(name: "Antônia", published: 60, inactive: nil)
                == "loja Antônia, 60 produtos: 60 publicados"
        )
        #expect(StoreBadgeText.accessibilityLabel(name: "loja B", published: nil, inactive: nil) == "loja B")
    }
}
