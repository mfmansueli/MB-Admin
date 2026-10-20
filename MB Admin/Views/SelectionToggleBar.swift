import SwiftUI

/// Botão "selecionar"/"cancelar seleção" + "selecionar todos"/"desmarcar todos" + o que estiver à
/// direita (a ação em massa disponível) — reaproveitado pela seleção múltipla de "publicados"
/// (`AccountDetailView`) e "inativos" (`InactiveProductsListView`).
struct SelectionToggleBar<TrailingContent: View>: View {
    @Binding var isSelecting: Bool
    let hasItems: Bool
    let isAllSelected: Bool
    let hasSelection: Bool
    let onToggleSelecting: () -> Void
    let onToggleSelectAll: () -> Void
    @ViewBuilder var trailingContent: () -> TrailingContent

    var body: some View {
        HStack(spacing: 6) {
            Button(isSelecting ? "cancelar seleção" : "selecionar", action: onToggleSelecting)
                .buttonStyle(.bordered)

            if isSelecting, hasItems {
                Button(isAllSelected ? "desmarcar todos" : "selecionar todos", action: onToggleSelectAll)
                    .buttonStyle(.bordered)
            }

            Spacer()

            if isSelecting, hasSelection {
                trailingContent()
            }
        }
    }
}
