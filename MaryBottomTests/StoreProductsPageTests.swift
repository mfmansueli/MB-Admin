import Foundation
import Testing
@testable import MaryBottom

@Suite("decodificação da listagem de produtos da loja")
struct StoreProductsPageTests {
    @Test("lê produtos, total e cursor da última aresta")
    func decodificaRespostaDoGraphQL() throws {
        let data = Data(EnjoeiFixtures.storeSearchJSON.utf8)

        let page = try JSONDecoder().decode(StoreProductsPage.self, from: data)

        #expect(page.total == 1495)
        #expect(page.products.map(\.id) == [145657034, 147640589])
        #expect(page.products.first?.title == "brinco argola estrela 50mm")
        #expect(page.products.first?.currentPrice == 273)
        // Sem `regularPrice` nesse recorte, cai pra `price.original`.
        #expect(page.products.first?.originalPrice == 399)
        // O cursor de continuação é o da última aresta: é ele que vai no parâmetro `after`.
        #expect(page.endCursor == "165537526022505319:1")
    }

    @Test("preço original prioriza regularPrice.values.price.listed sobre price.original")
    func preferePrecoOriginalDoRegularPrice() throws {
        let json = """
        {"data":{"seller":{"search":{"products":{"total":1,"edges":[
          {"cursor":"a","node":{
            "id":"1",
            "price":{"current":273,"original":399},
            "regularPrice":{"values":{"price":{"listed":599}}}
          }}
        ]}}}}}
        """
        let page = try JSONDecoder().decode(StoreProductsPage.self, from: Data(json.utf8))

        #expect(page.products.first?.originalPrice == 599)
    }

    @Test("página sem arestas encerra a paginação")
    func decodificaPaginaVazia() throws {
        let json = """
        {"data":{"seller":{"search":{"products":{"total":1495,"edges":[]}}}}}
        """
        let page = try JSONDecoder().decode(StoreProductsPage.self, from: Data(json.utf8))

        #expect(page.isEmpty)
        #expect(page.endCursor == nil)
    }

    @Test("descarta aresta sem id numérico em vez de falhar a página inteira")
    func ignoraProdutoInvalido() throws {
        let json = """
        {"data":{"seller":{"search":{"products":{"total":2,"edges":[
          {"cursor":"a","node":{"id":null,"title":{"name":"sem id"}}},
          {"cursor":"b","node":{"id":"42","title":{"name":"ok"}}}
        ]}}}}}
        """
        let page = try JSONDecoder().decode(StoreProductsPage.self, from: Data(json.utf8))

        #expect(page.products.map(\.id) == [42])
        #expect(page.endCursor == "b")
    }
}
