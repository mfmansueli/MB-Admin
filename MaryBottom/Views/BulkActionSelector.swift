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

            Button(action: onConfirm) {
                confirmIcon
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(selection.label) \(selectedCount) produtos")
        }
    }

    // Redimensionado explicitamente (em vez de só fixar a fonte) — sem isso, `doc.on.doc.fill`
    // (duas páginas sobrepostas, mais largo que os outros ícones do conjunto) estourava o círculo
    // em vez de ficar contido nele.
    private var confirmIcon: some View {
        let image = Image(systemName: selection.systemImage)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .frame(width: 38, height: 38)

        // O material "liquid glass" só existe a partir do iOS/Mac Catalyst 26 — mais velho que
        // isso cai de volta pro círculo colorido sólido de antes.
        return Group {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                image.glassEffect(.regular.tint(selection.tint).interactive(), in: .circle)
            } else {
                image.background(selection.tint, in: .circle)
            }
        }
    }
}
