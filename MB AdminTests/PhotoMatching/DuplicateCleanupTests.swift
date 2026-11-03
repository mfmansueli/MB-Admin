import Foundation
import Testing
@testable import MB_Admin

@Suite("escolher qual anúncio repetido fica e quais vão pra fila pra apagar")
struct DuplicateCleanupTests {
    typealias Fixtures = ComparisonFixtures

    private let products = [11, 7, 23].map { Fixtures.product($0, title: "anel coração", cover: "a\($0)") }
    private var group: StoreDuplicateGroup { Fixtures.duplicates(Fixtures.sellerA, products.sorted { $0.id < $1.id }) }

    @Test("sem escolha, fica o mais antigo (número menor) e os outros vão pra fila")
    func ficaOMaisAntigo() {
        #expect(DuplicateCleanup.kept(group, choice: nil, states: [:]) == 7)
        #expect(DuplicateCleanup.deletions(group, choice: nil, states: [:]).map(\.id) == [11, 23])
    }

    @Test("a escolha vale: fica ela, apaga o resto (o mais antigo inclusive)")
    func escolhaVale() {
        #expect(DuplicateCleanup.kept(group, choice: 23, states: [:]) == 23)
        #expect(DuplicateCleanup.deletions(group, choice: 23, states: [:]).map(\.id) == [7, 11])
    }

    @Test("\"talvez repetidos\" e \"não são repetidos\" nunca apagam nada — confirmado sim")
    func soGrupoCerto() {
        let ordered = products.sorted { $0.id < $1.id }
        for status in [StoreDuplicateGroup.Status.possible, .dismissed] {
            let group = Fixtures.duplicates(Fixtures.sellerA, ordered, status: status)
            #expect(!DuplicateCleanup.isSelectable(group, states: [:]))
            #expect(DuplicateCleanup.deletions(group, choice: 7, states: [:]).isEmpty)
        }
        let confirmed = Fixtures.duplicates(Fixtures.sellerA, ordered, status: .confirmed)
        #expect(DuplicateCleanup.deletions(confirmed, choice: 7, states: [:]).map(\.id) == [11, 23])
    }

    @Test("quem já está na fila não entra de novo, nem pode ser o que fica")
    func jaNaFila() {
        let states: [Int: DuplicateListingState] = [7: .queued]
        // A escolha caiu num que vai ser apagado: fica o mais antigo que continua na loja.
        #expect(DuplicateCleanup.kept(group, choice: 7, states: states) == 11)
        #expect(DuplicateCleanup.deletions(group, choice: 7, states: states).map(\.id) == [23])
    }

    @Test("com só um anúncio ainda na loja, não sobra nada pra apagar — nunca o produto inteiro")
    func nuncaApagaTodos() {
        for states in [[7: .deleted, 11: .queued], [7: .deleting, 23: .failed("erro")]] as [[Int: DuplicateListingState]] {
            #expect(!DuplicateCleanup.isSelectable(group, states: states))
            #expect(DuplicateCleanup.deletions(group, choice: nil, states: states).isEmpty)
        }
    }

    @Test("o estado de cada anúncio a partir da fila, do histórico e da conta")
    func estadoDoAnuncio() {
        #expect(DuplicateListingState.make(runnerStatus: nil, isQueued: false, wasDeleted: false) == .listed)
        #expect(DuplicateListingState.make(runnerStatus: nil, isQueued: true, wasDeleted: false) == .queued)
        #expect(DuplicateListingState.make(runnerStatus: .megaphoning, isQueued: true, wasDeleted: false) == .deleting)
        #expect(DuplicateListingState.make(runnerStatus: .succeeded, isQueued: true, wasDeleted: false) == .deleted)
        // Depois de fechar o app, só o histórico sabe.
        #expect(DuplicateListingState.make(runnerStatus: nil, isQueued: false, wasDeleted: true) == .deleted)
        #expect(DuplicateListingState.make(runnerStatus: .failed("404"), isQueued: true, wasDeleted: false) == .failed("404"))
        // Falhou e você tirou da fila: continua na loja.
        #expect(DuplicateListingState.make(runnerStatus: .failed("404"), isQueued: false, wasDeleted: false) == .listed)
    }
}
