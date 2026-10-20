import Foundation
import Testing
@testable import MB_Admin

@Suite("decodificação da resposta de criar produto")
struct ProductCreateResponseTests {
    @Test("lê o path quando a resposta traz um")
    func lePath() throws {
        let json = #"{"path": "colar-curto-149812846"}"#
        let response = try JSONDecoder().decode(ProductCreateResponse.self, from: Data(json.utf8))
        #expect(response.path == "colar-curto-149812846")
    }

    @Test("corpo sem path decodifica sem erro")
    func semPath() throws {
        let response = try JSONDecoder().decode(ProductCreateResponse.self, from: Data("{}".utf8))
        #expect(response.path == nil)
    }

    @Test("também lê o path quando vem aninhado em product, espelhando o corpo da criação")
    func lePathAninhadoEmProduct() throws {
        let json = #"{"product": {"path": "colar-curto-149812846"}}"#
        let response = try JSONDecoder().decode(ProductCreateResponse.self, from: Data(json.utf8))
        #expect(response.path == "colar-curto-149812846")
    }

    @Test("lê slug como path quando não há path")
    func leSlug() throws {
        let json = #"{"slug": "colar-curto-149812846"}"#
        let response = try JSONDecoder().decode(ProductCreateResponse.self, from: Data(json.utf8))
        #expect(response.path == "colar-curto-149812846")
    }

    @Test("lê url como path quando não há path nem slug")
    func leURL() throws {
        let json = #"{"url": "colar-curto-149812846"}"#
        let response = try JSONDecoder().decode(ProductCreateResponse.self, from: Data(json.utf8))
        #expect(response.path == "colar-curto-149812846")
    }

    @Test("slug/url aninhados em product também são lidos")
    func leSlugAninhadoEmProduct() throws {
        let json = #"{"product": {"slug": "colar-curto-149812846"}}"#
        let response = try JSONDecoder().decode(ProductCreateResponse.self, from: Data(json.utf8))
        #expect(response.path == "colar-curto-149812846")
    }

    @Test("path tem prioridade sobre slug e url quando os dois vêm juntos")
    func prioridadeDoPath() throws {
        let json = #"{"path": "path-certo", "slug": "slug-errado", "url": "url-errada"}"#
        let response = try JSONDecoder().decode(ProductCreateResponse.self, from: Data(json.utf8))
        #expect(response.path == "path-certo")
    }
}
