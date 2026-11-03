import Foundation
import Testing
@testable import MB_Admin

@Suite("intervalos da fila por tipo de ação")
struct PostQueueIntervalGroupTests {
    @Test("postar, repostar e apagar num grupo; inativar no outro")
    func grupoDeCadaAcao() {
        #expect(PostQueueIntervalGroup(kind: .post) == .posting)
        #expect(PostQueueIntervalGroup(kind: .delete) == .posting)
        #expect(PostQueueIntervalGroup(kind: .inactivate) == .inactivating)
        // Um "ativar" que ficou na fila de antes anda no ritmo de inativar.
        #expect(PostQueueIntervalGroup(kind: .activate) == .inactivating)
    }

    @Test("postar, repostar e apagar: 30s de padrão e de mínimo; inativar: 15s")
    func padroesEOpcoes() {
        #expect(PostQueueIntervalGroup.posting.defaultInterval == 30)
        #expect(PostQueueIntervalGroup.posting.minimumInterval == 30)
        #expect(PostQueueIntervalGroup.inactivating.defaultInterval == 15)
        #expect(PostQueueIntervalGroup.inactivating.minimumInterval == 15)
        #expect(PostQueueIntervalGroup.posting.presets == [30, 60, 120, 180, 240, 300])
        #expect(PostQueueIntervalGroup.inactivating.presets == [15, 30, 60, 120, 180, 240, 300])
        for group in PostQueueIntervalGroup.allCases {
            #expect(group.presets.allSatisfy { $0 >= group.minimumInterval })
        }
    }

    @Test("os nomes dos grupos no menu e no cartão da fila")
    func titulos() {
        #expect(PostQueueIntervalGroup.posting.title == "postar, repostar e apagar")
        #expect(PostQueueIntervalGroup.inactivating.title == "inativar")
    }

    @Test("postar guarda na chave de antes dos grupos; inativar ganhou chave nova, pra começar nos 15s")
    func chaves() {
        #expect(PostQueueIntervalGroup.posting.defaultsKey == "postQueue.interval")
        #expect(PostQueueIntervalGroup.inactivating.defaultsKey == "postQueue.interval.inactivate")
    }
}
