import SwiftUI

/// Menu de escolher a ação em massa + botão de confirmar — reaproveitado pela seleção múltipla de
/// "publicados" (`AccountDetailView`) e "inativos" (`InactiveProductsListView`), cada uma passando
/// seu próprio `BulkActionOption`.
struct BulkActionSelector<Action: BulkActionOption>: View {
    @Binding var selection: Action
    let selectedCount: Int
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("ação", selection: $selection) {
                    ForEach(Array(Action.allCases), id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(selection.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }

            BulkConfirmButton(
                systemImage: selection.systemImage,
                tint: selection.tint,
                accessibilityLabel: "\(selection.label) \(selectedCount) produtos",
                action: onConfirm
            )
        }
    }
}
