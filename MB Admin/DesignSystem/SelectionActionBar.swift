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
                .foregroundStyle(style(for: action.role))
                // Sem isso, o VoiceOver lê o nome do símbolo junto ("lixeira, apagar").
                .accessibilityLabel(action.label)
            }
        }
        .disabled(!isEnabled)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassSurface(in: .capsule)
        .frame(maxWidth: 660)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Sem nada marcado (é assim que a seleção começa), cinza secundário em vez de baixar a
    /// opacidade da barra — a 40% em cima do vidro, com a lista aparecendo por trás, os rótulos
    /// ficavam quase ilegíveis.
    private func style(for role: SelectionBarActionRole) -> AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.secondary) }
        return switch role {
        case .standard: AnyShapeStyle(.primary)
        case .decision: AnyShapeStyle(.statusDecision)
        case .destructive: AnyShapeStyle(.statusFailure)
        }
    }
}

/// As mesmas ações habilitadas e desabilitadas, em cima de texto — a barra de verdade flutua sobre a
/// lista, e é aí que dá pra ver se o estado desabilitado continua legível.
#Preview {
    ZStack(alignment: .bottom) {
        List(0..<20) { index in
            Text("anel aro 17 entrelaçado cravejado zircônia \(index)")
        }
        VStack(spacing: 0) {
            SelectionActionBar(actions: PublishedBulkAction.allCases, isEnabled: true) { _ in }
            SelectionActionBar(actions: PublishedBulkAction.allCases, isEnabled: false) { _ in }
            SelectionActionBar(actions: InactiveBulkAction.allCases, isEnabled: false) { _ in }
        }
    }
}
