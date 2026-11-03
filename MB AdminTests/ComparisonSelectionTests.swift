import Foundation
import Testing
@testable import MB_Admin

@Suite("seleção no resultado da comparação: ausentes e grupos de repetidos")
struct ComparisonSelectionTests {
    @Test("escolher o anúncio que fica marca o grupo, e a escolha sobrevive a desmarcar")
    func escolherMarcaOGrupo() {
        var selection = ComparisonSelection()
        selection.keep(42, inGroup: "repetidos-1-40")
        #expect(selection.groupIDs == ["repetidos-1-40"])
        #expect(selection.keptByGroup["repetidos-1-40"] == 42)

        selection.toggle(groupID: "repetidos-1-40")
        #expect(selection.groupIDs.isEmpty)
        #expect(selection.keptByGroup["repetidos-1-40"] == 42)
    }

    @Test("\"todos\" marca produtos e grupos juntos; de novo, desmarca só esses")
    func todosENenhum() {
        var selection = ComparisonSelection()
        selection.toggle(productID: 99)
        selection.toggleAll(productIDs: [1, 2], groupIDs: ["g"])
        #expect(selection.isFullySelected(productIDs: [1, 2], groupIDs: ["g"]))
        #expect(selection.count == 4)

        selection.toggleAll(productIDs: [1, 2], groupIDs: ["g"])
        #expect(selection.productIDs == [99])
        #expect(selection.groupIDs.isEmpty)
        #expect(!selection.isFullySelected(productIDs: [], groupIDs: []))
    }

    @Test("o que sai da tela sai da seleção; mandar uma parte pra fila deixa a outra marcada")
    func manterSoOQueEstaNaTela() {
        var selection = ComparisonSelection()
        selection.toggle(productID: 1)
        selection.toggle(productID: 2)
        selection.select(groupID: "g1")
        selection.select(groupID: "g2")
        selection.keepOnly(productIDs: [2], groupIDs: ["g2"])
        #expect(selection.productIDs == [2])
        #expect(selection.groupIDs == ["g2"])

        selection.removeGroups()
        #expect(!selection.isEmpty)
        selection.removeProducts()
        #expect(selection.isEmpty)
    }
}
