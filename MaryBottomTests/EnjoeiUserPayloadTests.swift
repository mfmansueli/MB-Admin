import Foundation
import Testing
@testable import MaryBottom

@Suite("decodificação do usuário do enjoei")
struct EnjoeiUserPayloadTests {
    @Test("converte a resposta da API no usuário do app")
    func decodificaUsuarioLogado() throws {
        let data = Data(EnjoeiFixtures.currentUserJSON.utf8)

        let payload = try JSONDecoder().decode(EnjoeiUserPayload.self, from: data)
        let user = payload.makeUser()

        #expect(user?.id == 28714888)
        #expect(user?.nickname == "antonia-40d0aa")
        #expect(user?.name == "antonia")
        #expect(user?.availableProductsCount == 1496)
        #expect(user?.avatarURL?.absoluteString
            == "https://photos.enjoei.com.br/public/100x100/czM6Ly9hdmF0YXI")
    }

    @Test("corpo vazio de visitante não vira usuário")
    func visitanteNaoViraUsuario() throws {
        let payload = try JSONDecoder().decode(EnjoeiUserPayload.self, from: Data("{}".utf8))

        #expect(payload.makeUser() == nil)
    }

    @Test("usa o apelido como nome quando a API não manda o nome")
    func usaApelidoComoNome() throws {
        let json = #"{"id": 1, "nickname": "loja-teste"}"#
        let payload = try JSONDecoder().decode(EnjoeiUserPayload.self, from: Data(json.utf8))

        #expect(payload.makeUser()?.name == "loja-teste")
    }
}
