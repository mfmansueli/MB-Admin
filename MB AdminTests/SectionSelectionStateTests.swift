import Foundation
import Testing
@testable import MB_Admin

@Suite("seleção de uma seção de publicados")
struct SectionSelectionStateTests {
    @Test("nenhum, alguns ou todos os ids da seção marcados")
    func estadoPelaSelecao() {
        let ids = [1, 2, 3]

        #expect(SectionSelectionState(sectionIDs: ids, selectedIDs: []) == .noneSelected)
        #expect(SectionSelectionState(sectionIDs: ids, selectedIDs: [2]) == .someSelected)
        #expect(SectionSelectionState(sectionIDs: ids, selectedIDs: [1, 2, 3]) == .allSelected)
    }

    @Test("marcados de outra seção não contam")
    func ignoraOutrasSecoes() {
        #expect(SectionSelectionState(sectionIDs: [1, 2], selectedIDs: [3, 4]) == .noneSelected)
        #expect(SectionSelectionState(sectionIDs: [1, 2], selectedIDs: [1, 2, 3]) == .allSelected)
    }

    @Test("seção vazia não tem o que desmarcar")
    func secaoVazia() {
        #expect(SectionSelectionState(sectionIDs: [], selectedIDs: [1]) == .noneSelected)
    }

    @Test("círculo do cabeçalho: vazio, com \"–\" e com o check")
    func simboloDoCirculo() {
        #expect(SectionSelectionState.noneSelected.symbolName == "circle")
        #expect(SectionSelectionState.someSelected.symbolName == "minus.circle.fill")
        #expect(SectionSelectionState.allSelected.symbolName == "checkmark.circle.fill")
    }

    @Test("cápsula: selecionar os N enquanto faltar algum, desmarcar os N com a seção inteira marcada")
    func rotuloDaCapsula() {
        #expect(SectionSelectionState.noneSelected.toggleAllLabel(count: 3) == "selecionar os 3")
        #expect(SectionSelectionState.someSelected.toggleAllLabel(count: 3) == "selecionar os 3")
        #expect(SectionSelectionState.allSelected.toggleAllLabel(count: 3) == "desmarcar os 3")
    }

    @Test("com um produto só, no singular")
    func rotuloNoSingular() {
        #expect(SectionSelectionState.noneSelected.toggleAllLabel(count: 1) == "selecionar o 1")
        #expect(SectionSelectionState.allSelected.toggleAllLabel(count: 1) == "desmarcar o 1")
    }

    @Test("VoiceOver diz de qual seção se trata")
    func rotuloDeAcessibilidade() {
        #expect(
            SectionSelectionState.someSelected.toggleAllAccessibilityLabel(count: 3, sectionTitle: "pedem desconto")
                == "selecionar os 3 de pedem desconto"
        )
        #expect(
            SectionSelectionState.allSelected.toggleAllAccessibilityLabel(count: 3, sectionTitle: "pedem desconto")
                == "desmarcar os 3 de pedem desconto"
        )
    }
}
