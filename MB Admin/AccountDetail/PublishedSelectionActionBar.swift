import SwiftUI

/// Barra de vidro com as ações em massa da seleção múltipla de "publicados" — ícone em cima do
/// rótulo, uma ao lado da outra. Tocar só pede a confirmação (quem usa mostra o alerta); nada entra
/// na fila sem ela.
struct PublishedSelectionActionBar: View {
    let actions: [PublishedBulkAction]
    let isEnabled: Bool
    let onSelect: (PublishedBulkAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    onSelect(action)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: action.systemImage)
                            .font(.title3)
                        Text(action.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(color(for: action))
                // Sem isso, o VoiceOver lê o nome do símbolo junto ("lixeira, apagar").
                .accessibilityLabel(action.label)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassSurface(in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func color(for action: PublishedBulkAction) -> Color {
        switch action {
        case .applyDiscount: .statusDecision
        case .delete: .statusFailure
        case .repost, .inactivate: .primary
        }
    }
}

#Preview {
    VStack {
        Spacer()
        PublishedSelectionActionBar(actions: PublishedBulkAction.allCases, isEnabled: true) { _ in }
        PublishedSelectionActionBar(actions: [.repost, .inactivate, .delete], isEnabled: false) { _ in }
    }
}
