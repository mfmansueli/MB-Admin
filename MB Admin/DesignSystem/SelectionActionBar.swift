import SwiftUI

/// Barra de vidro com as ações em massa de uma seleção múltipla ("publicados", "inativos") — ícone
/// em cima do rótulo, uma ao lado da outra. Tocar só pede a confirmação (quem usa mostra o alerta);
/// nada entra na fila sem ela.
struct SelectionActionBar<Action: SelectionBarAction>: View {
    let actions: [Action]
    let isEnabled: Bool
    let onSelect: (Action) -> Void

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
                .foregroundStyle(color(for: action.role))
                // Sem isso, o VoiceOver lê o nome do símbolo junto ("lixeira, apagar").
                .accessibilityLabel(action.label)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassSurface(in: .capsule)
        .frame(maxWidth: 660)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func color(for role: SelectionBarActionRole) -> Color {
        switch role {
        case .standard: .primary
        case .decision: .statusDecision
        case .destructive: .statusFailure
        }
    }
}

#Preview {
    VStack {
        Spacer()
        SelectionActionBar(actions: PublishedBulkAction.allCases, isEnabled: true) { _ in }
        SelectionActionBar(actions: InactiveBulkAction.allCases, isEnabled: false) { _ in }
    }
}
