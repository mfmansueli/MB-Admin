import SwiftUI

/// Cabeçalho recolhível de uma seção da aba "publicados" ("pedem desconto · 3", "todos os anúncios ·
/// 1.493") — o título inteiro é o alvo de toque, não só a seta. Selecionando, ganha um círculo à
/// esquerda (nenhum/alguns/todos da seção marcados) e uma cápsula "selecionar os N" à direita, os
/// dois só daquela seção.
struct PublishedSectionHeader: View {
    let title: String
    let count: Int
    /// Cor do título — "pedem desconto" usa a cor de "pede decisão"; o resto fica no texto padrão.
    var titleColor: Color?
    let isCollapsed: Bool
    var horizontalPadding: CGFloat = 16
    /// Quanto da seção está marcado — `nil` fora do modo de seleção (sem círculo nem cápsula).
    var selectionState: SectionSelectionState?
    var onSelectAll: () -> Void = {}
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let selectionState {
                // Botão irmão do cabeçalho, não dentro dele — pelo mesmo motivo da cápsula abaixo.
                // Fora do VoiceOver: faz o mesmo que a cápsula, que já diz o que acontece.
                Button(action: onSelectAll) {
                    selectionCircle(selectionState)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }

            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    // Uma linha só, com prioridade sobre o botão ao lado: no tamanho de letra do app,
                    // o título quebrava em duas pra caber a cápsula de selecionar. No iPhone, com o
                    // círculo e a cápsula da seleção juntos, encolhe um pouco antes de cortar.
                    Text(title)
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                    // Nunca quebra: sem isso, no iPhone o "·" e o número iam um embaixo do outro
                    // quando a cápsula ao lado apertava a linha.
                    Text("· \(count.formatted())")
                        .fontWeight(.medium)
                        .foregroundStyle(.supportingText)
                        .monospacedDigit()
                        .fixedSize()
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isCollapsed ? "recolhida" : "aberta")
            .accessibilityHint(isCollapsed ? "toque para mostrar" : "toque para esconder")

            if let selectionState {
                // Botão irmão do cabeçalho, não dentro dele — um botão dentro do outro faria o
                // toque na cápsula também recolher a seção.
                selectAllCapsule(selectionState)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 6)
        // Mesmo motivo do fundo sólido de `MegaphoneRowView`: sem pixel desenhado, o scroll do
        // mouse no Mac Catalyst não pega em cima do cabeçalho.
        .background(.background)
    }

    /// Mesmo tamanho e cores do círculo de cada linha (`MegaphoneRowView.selectionIndicator`), pra
    /// ficar alinhado na mesma coluna deles.
    private func selectionCircle(_ state: SectionSelectionState) -> some View {
        let isMarked = state != .noneSelected
        return Image(systemName: state.symbolName)
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isMarked ? AnyShapeStyle(Color.onTint) : AnyShapeStyle(Color(uiColor: .tertiaryLabel)),
                isMarked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear)
            )
            .contentShape(.rect)
    }

    /// Texto limitado ao `.xLarge`, abaixo do `.xxxLarge` do resto do app — mesmo motivo da barra
    /// de baixo de "publicados" no iPhone: no tamanho cheio, círculo, título, contagem e cápsula não
    /// cabem lado a lado.
    @ViewBuilder
    private func selectAllCapsule(_ state: SectionSelectionState) -> some View {
        let button = Button(state.toggleAllLabel(count: count), action: onSelectAll)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .fixedSize()
            .accessibilityLabel(state.toggleAllAccessibilityLabel(count: count, sectionTitle: title))
        if state == .allSelected {
            // Os estilos proeminentes pintam o texto de branco, que some em cima da cor de destaque
            // no modo escuro (`#F2F2F7`) — ver `ProminentGlassButtonStyleModifier`.
            button
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.onTint)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var titleStyle: AnyShapeStyle {
        if let titleColor { AnyShapeStyle(titleColor) } else { AnyShapeStyle(.primary) }
    }
}

#Preview {
    VStack(spacing: 0) {
        PublishedSectionHeader(title: "pedem desconto", count: 3, titleColor: .statusDecision, isCollapsed: false) {}
        PublishedSectionHeader(title: "todos os anúncios", count: 1493, isCollapsed: true) {}
        PublishedSectionHeader(
            title: "pedem desconto",
            count: 3,
            titleColor: .statusDecision,
            isCollapsed: false,
            selectionState: .allSelected
        ) {}
        PublishedSectionHeader(
            title: "todos os anúncios",
            count: 1493,
            isCollapsed: false,
            selectionState: .someSelected
        ) {}
        PublishedSectionHeader(
            title: "todos os anúncios",
            count: 1493,
            isCollapsed: false,
            selectionState: .noneSelected
        ) {}
    }
}
