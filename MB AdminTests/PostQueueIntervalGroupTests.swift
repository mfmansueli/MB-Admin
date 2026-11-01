import Foundation
import Testing
@testable import MB_Admin

@Suite("intervalos da fila por tipo de ação")
struct PostQueueIntervalGroupTests {
    @Test("postar e repostar num grupo; ativar, inativar e apagar no outro")
    func grupoDeCadaAcao() {
        #expect(PostQueueIntervalGroup(kind: .post) == .posting)
        #expect(PostQueueIntervalGroup(kind: .delete) == .listingChange)
        #expect(PostQueueIntervalGroup(kind: .inactivate) == .listingChange)
        #expect(PostQueueIntervalGroup(kind: .activate) == .listingChange)
    }

    @Test("30s de padrão pra postar; ativar, inativar e apagar começam em 10s e descem até 5s")
    func padroesEOpcoes() {
        #expect(PostQueueIntervalGroup.posting.defaultInterval == 30)
        #expect(PostQueueIntervalGroup.listingChange.defaultInterval == 10)
        #expect(PostQueueIntervalGroup.posting.presets == [30, 60, 120, 180, 240, 300])
        #expect(PostQueueIntervalGroup.listingChange.presets == [5, 10, 15, 30, 60, 120, 180, 240, 300])
        for group in PostQueueIntervalGroup.allCases {
            #expect(group.presets.contains(group.defaultInterval))
        }
    }

    @Test("os nomes dos grupos no menu e no cartão da fila")
    func titulos() {
        #expect(PostQueueIntervalGroup.posting.title == "postar e repostar")
        #expect(PostQueueIntervalGroup.listingChange.title == "ativar, inativar e apagar")
    }

    @Test("postar guarda na chave de antes dos grupos; o grupo de apagar ganhou chave nova, pra começar nos 10s")
    func chaves() {
        #expect(PostQueueIntervalGroup.posting.defaultsKey == "postQueue.interval")
        #expect(PostQueueIntervalGroup.listingChange.defaultsKey == "postQueue.interval.listingChange")
    }
}
