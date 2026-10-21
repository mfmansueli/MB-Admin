import SwiftUI

/// Cabeçalho recolhível de uma seção da aba "publicados" ("pedem desconto · 3", "todos os anúncios ·
/// 1.493") — o título inteiro é o alvo de toque, não só a seta. Selecionando, ganha à direita um
/// "todos"/"nenhum" só daquela seção.
struct PublishedSectionHeader: View {
    let title: String
    let count: Int
    /// Cor do título — "pedem desconto" usa a cor de "pede decisão"; o resto fica no texto padrão.
    var titleColor: Color?
    let isCollapsed: Bool
    var horizontalPadding: CGFloat = 16
    /// Se a seção inteira já está marcada — `nil` fora do modo de seleção (sem botão).
    var isFullySelected: Bool?
    var onSelectAll: () -> Void = {}
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    // Uma linha só, com prioridade sobre o botão ao lado: no tamanho de letra do app,
                    // o título quebrava em duas pra caber o "todos".
                    Text(title)
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text("· \(count.formatted())")
                        .fontWeight(.medium)
                        .foregroundStyle(.supportingText)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isCollapsed ? "recolhida" : "aberta")
            .accessibilityHint(isCollapsed ? "toque para mostrar" : "toque para esconder")

            if let isFullySelected {
                // Botão irmão do cabeçalho, não dentro dele — um botão dentro do outro faria o
                // toque em "todos" também recolher a seção. Mesmo "todos"/"nenhum" curto do botão
                // da barra de cima; o VoiceOver lê a versão completa.
                Button(isFullySelected ? "nenhum" : "todos", action: onSelectAll)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .fixedSize()
                    .accessibilityLabel(isFullySelected ? "desmarcar todos em \(title)" : "selecionar todos em \(title)")
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

    private var titleStyle: AnyShapeStyle {
        if let titleColor { AnyShapeStyle(titleColor) } else { AnyShapeStyle(.primary) }
    }
}

#Preview {
    VStack(spacing: 0) {
        PublishedSectionHeader(title: "pedem desconto", count: 3, titleColor: .statusDecision, isCollapsed: false) {}
        PublishedSectionHeader(title: "todos os anúncios", count: 1493, isCollapsed: true) {}
        PublishedSectionHeader(
            title: "todos os anúncios",
            count: 1493,
            isCollapsed: false,
            isFullySelected: false
        ) {}
    }
}
