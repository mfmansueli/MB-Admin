import Foundation
import Testing
@testable import MB_Admin

@Suite("intervalos da fila por tipo de ação")
struct PostQueueIntervalGroupTests {
    @Test("postar, repostar e apagar num grupo; ativar e inativar no outro")
    func grupoDeCadaAcao() {
        #expect(PostQueueIntervalGroup(kind: .post) == .posting)
        #expect(PostQueueIntervalGroup(kind: .delete) == .posting)
        #expect(PostQueueIntervalGroup(kind: .inactivate) == .statusChange)
        #expect(PostQueueIntervalGroup(kind: .activate) == .statusChange)
    }

    @Test("30s de padrão pra postar; 15s só existe pra ativar e inativar, e é o padrão delas")
    func padroesEOpcoes() {
        #expect(PostQueueIntervalGroup.posting.defaultInterval == 30)
        #expect(PostQueueIntervalGroup.statusChange.defaultInterval == 15)
        #expect(PostQueueIntervalGroup.posting.presets == [30, 60, 120, 180, 240, 300])
        #expect(PostQueueIntervalGroup.statusChange.presets == [15, 30, 60, 120, 180, 240, 300])
        for group in PostQueueIntervalGroup.allCases {
            #expect(group.presets.contains(group.defaultInterval))
        }
    }

    @Test("postar guarda na chave de antes dos grupos, pra não perder a escolha já feita")
    func chaves() {
        #expect(PostQueueIntervalGroup.posting.defaultsKey == "postQueue.interval")
        #expect(PostQueueIntervalGroup.statusChange.defaultsKey == "postQueue.interval.statusChange")
    }
}
