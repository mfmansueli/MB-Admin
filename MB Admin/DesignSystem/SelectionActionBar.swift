import SwiftUI

/// Barra de vidro com as ações em massa de uma seleção múltipla ("publicados", "inativos") — ícone
/// em cima do rótulo, uma ao lado da outra. Tocar só pede a confirmação (quem usa mostra o alerta);
/// nada entra na fila sem ela. Uma ação que ainda precisa de uma escolha antes (`opensMenu`, ex.: a
/// loja de "postar em") abre um menu com o `menuContent` dela, e é a escolha nele que segue pra
/// confirmação.
struct SelectionActionBar<Action: SelectionBarAction, MenuContent: View>: View {
    let actions: [Action]
    let isEnabled: Bool
    /// Ações que ficam à mostra, mas em cinza e sem responder, mesmo com algo selecionado (ex.:
    /// "postar em" sem nenhuma outra loja com sessão aberta).
    var disabledActions: Set<Action> = []
    let onSelect: (Action) -> Void
    @ViewBuilder let menuContent: (Action) -> MenuContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        actions: [Action],
        isEnabled: Bool,
        disabledActions: Set<Action> = [],
        onSelect: @escaping (Action) -> Void,
        @ViewBuilder menuContent: @escaping (Action) -> MenuContent
    ) {
        self.actions = actions
        self.isEnabled = isEnabled
        self.disabledActions = disabledActions
        self.onSelect = onSelect
        self.menuContent = menuContent
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                let isActionEnabled = isEnabled && !disabledActions.contains(action)
                Group {
                    if action.opensMenu {
                        Menu {
                            menuContent(action)
                        } label: {
                            label(for: action)
                        }
                        .menuStyle(.button)
                        // Aberto da barra de baixo, o menu cresce pra cima e o iOS inverte a ordem
                        // dos itens (o primeiro fica mais perto do dedo) — as lojas de "postar em"
                        // têm que seguir a ordem da lista de contas.
                        .menuOrder(.fixed)
                    } else {
                        Button {
                            onSelect(action)
                        } label: {
                            label(for: action)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(style(for: action.role, isEnabled: isActionEnabled))
                .disabled(!isActionEnabled)
                // Sem isso, o VoiceOver lê o nome do símbolo junto ("lixeira, apagar").
                .accessibilityLabel(action.label)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassSurface(in: .capsule)
        .frame(maxWidth: 660)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func label(for action: Action) -> some View {
        VStack(spacing: 2) {
            Image(systemName: action.systemImage)
                .font(.title3)
            Text(horizontalSizeClass == .regular ? action.label : action.compactLabel)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(.rect)
    }

    /// Sem nada marcado (é assim que a seleção começa), cinza secundário em vez de baixar a
    /// opacidade da barra — a 40% em cima do vidro, com a lista aparecendo por trás, os rótulos
    /// ficavam quase ilegíveis.
    private func style(for role: SelectionBarActionRole, isEnabled: Bool) -> AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.secondary) }
        return switch role {
        case .standard: AnyShapeStyle(.primary)
        case .decision: AnyShapeStyle(.statusDecision)
        case .destructive: AnyShapeStyle(.statusFailure)
        }
    }
}

extension SelectionActionBar where MenuContent == EmptyView {
    /// Só com ações diretas, sem nenhuma que abra menu.
    init(
        actions: [Action],
        isEnabled: Bool,
        disabledActions: Set<Action> = [],
        onSelect: @escaping (Action) -> Void
    ) {
        self.init(actions: actions, isEnabled: isEnabled, disabledActions: disabledActions, onSelect: onSelect) { _ in
            EmptyView()
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
            SelectionActionBar(actions: PublishedBulkAction.allCases, isEnabled: true) { _ in } menuContent: { _ in
                Button("loja B") {}
                Button("loja C") {}
            }
            SelectionActionBar(actions: PublishedBulkAction.allCases, isEnabled: true, disabledActions: [.postToOtherStore]) { _ in }
            SelectionActionBar(actions: PublishedBulkAction.allCases, isEnabled: false) { _ in }
            SelectionActionBar(actions: InactiveBulkAction.allCases, isEnabled: false) { _ in }
        }
    }
}
