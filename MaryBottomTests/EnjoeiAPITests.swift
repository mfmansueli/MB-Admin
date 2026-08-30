import Foundation
import Testing
@testable import MaryBottom

@Suite("montagem das URLs do enjoei")
struct EnjoeiAPITests {
    @Test("primeira página da loja não manda cursor")
    func primeiraPaginaSemCursor() throws {
        let url = EnjoeiAPI.storeProductsURL(sellerID: 28714888, after: nil, browserID: "abc-1")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value) })

        #expect(url.host() == "enjusearch.enjoei.com.br")
        #expect(values["seller_id"] == "28714888")
        #expect(values["user_id"] == "28714888")
        #expect(values["first"] == "50")
        #expect(values["query_id"] == EnjoeiAPI.searchQueryID)
        #expect(values["browser_id"] == "abc-1")
        #expect(values["after"] == nil)
    }

    @Test("páginas seguintes mandam o cursor recebido")
    func paginaSeguinteComCursor() throws {
        let url = EnjoeiAPI.storeProductsURL(sellerID: 1, after: "165537480022315115:1", browserID: "abc-1")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(query.contains(URLQueryItem(name: "after", value: "165537480022315115:1")))
    }

    @Test("rotas de usuário e megafone")
    func rotasFixas() {
        #expect(EnjoeiAPI.currentUserURL.absoluteString
            == "https://www.enjoei.com.br/api/v3/current_user.json")
        #expect(EnjoeiAPI.userURL(nickname: "antonia-40d0aa").absoluteString
            == "https://www.enjoei.com.br/api/v3/users/antonia-40d0aa.json")
        #expect(EnjoeiAPI.megaphonesURL.absoluteString == "https://www.enjoei.com.br/api/megaphones")
        #expect(EnjoeiAPI.loginURL.absoluteString == "https://www.enjoei.com.br/usuario/identifique-se")
        #expect(EnjoeiAPI.productURL(path: "brinco-argola-estrela-145657034").absoluteString
            == "https://www.enjoei.com.br/p/brinco-argola-estrela-145657034")
    }

}
