import Foundation
import Testing
@testable import MaryBottom

@Suite("URLs das fotos do enjoei")
struct EnjoeiPhotoTests {
    @Test("monta a URL no formato host/visibilidade/tamanho/public_id")
    func montaURLDaFoto() {
        let url = EnjoeiPhoto.url(publicID: "czM6Ly9waG90b3M", size: .thumbnail)

        #expect(url?.absoluteString == "https://photos.enjoei.com.br/public/300x300/czM6Ly9waG90b3M")
    }

    @Test("public id vazio não vira URL")
    func publicIDVazio() {
        #expect(EnjoeiPhoto.url(publicID: "", size: .card) == nil)
    }
}
