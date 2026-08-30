import Foundation
import Testing
@testable import MaryBottom

@Suite("extração de dados do HTML do enjoei")
struct EnjoeiHTMLScraperTests {
    @Test("pega o token CSRF da meta tag")
    func extraiTokenCSRF() {
        let html = #"<meta name="csrf-param" content="authenticity_token"/><meta name="csrf-token" content="abc123=="/>"#

        #expect(EnjoeiHTMLScraper.csrfToken(inHTML: html) == "abc123==")
    }

    @Test("aceita a meta tag com os atributos invertidos")
    func extraiTokenComAtributosInvertidos() {
        let html = #"<meta content="xyz789" name="csrf-token">"#

        #expect(EnjoeiHTMLScraper.csrfToken(inHTML: html) == "xyz789")
    }

    @Test("token vazio (página de visitante) conta como ausente")
    func tokenVazioEhNil() {
        // É exatamente o que o Enjoei renderiza para quem não está logado.
        let html = #"<meta name="csrf-token" content=""/>"#

        #expect(EnjoeiHTMLScraper.csrfToken(inHTML: html) == nil)
    }

    @Test("pega o apelido da loja pela URL final do redirecionamento")
    func extraiApelidoDaURL() {
        let url = URL(string: "https://www.enjoei.com.br/@antonia-40d0aa")!

        #expect(EnjoeiHTMLScraper.storeNickname(inURL: url) == "antonia-40d0aa")
    }

    @Test("redirecionamento de visitante não vira apelido")
    func ignoraRedirecionamentoDeVisitante() {
        // Sem sessão, /minha-loja só vira /@minha-loja — não é a loja de ninguém.
        let url = URL(string: "https://www.enjoei.com.br/@minha-loja")!

        #expect(EnjoeiHTMLScraper.storeNickname(inURL: url) == nil)
        #expect(EnjoeiHTMLScraper.storeNickname(inURL: EnjoeiAPI.webBaseURL) == nil)
    }
}
