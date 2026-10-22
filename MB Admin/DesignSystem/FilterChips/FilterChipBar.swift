import SwiftUI

/// Fileira de filtros em cápsula, à vista embaixo do seletor de abas — no lugar do menu de filtro
/// que ficava escondido na barra de cima. O escolhido fica preenchido (`.borderedProminent`), os
/// outros só com o fundo cinza (`.bordered`); cada um mostra quantos produtos caem nele.
///
/// Rola na horizontal quando não cabe (no iPhone, os de "sem preço esperto" passam da largura da
/// tela). Mora no conteúdo da barra presa no topo (`floatingTopBar`), não em `ToolbarItem`: no Mac
/// Catalyst, botão de toolbar vira `NSToolbarButton`, e trocar o estado dele derruba o app (ver
/// `ToolbarItemDisabled`).
struct FilterChipBar<Value: Hashable>: View {
    let options: [FilterChipOption<Value>]
    @Binding var selection: Value
    var horizontalPadding: CGFloat = 16

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    chip(option)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    @ViewBuilder
    private func chip(_ option: FilterChipOption<Value>) -> some View {
        let isSelected = option.value == selection
        let button = Button {
            selection = option.value
        } label: {
            HStack(spacing: 6) {
                if let dotColor = option.dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                }
                Text(option.label)
                    .fontWeight(.medium)
                Text(option.count.formatted())
                    // No preenchido, o cinza de apoio some no fundo escuro (e no quase branco do
                    // modo escuro) — lá o número fica na cor do texto, só mais apagado.
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.onTint.opacity(0.7)) : AnyShapeStyle(.supportingText))
                    .monospacedDigit()
            }
            // Mesmo tamanho do título das seções logo abaixo — no `.body` do app, as cápsulas ficavam
            // maiores que o próprio seletor de abas acima delas.
            .font(.subheadline)
            .lineLimit(1)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if isSelected {
            // Os estilos proeminentes pintam o texto de branco, que some em cima da cor de destaque
            // no modo escuro (`#F2F2F7`) — mesmo cuidado de `ProminentGlassButtonStyleModifier`.
            button
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.onTint)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

#Preview {
    @Previewable @State var filter = AccountProductFilter.all
    @Previewable @State var smartPriceFilter = "atual"
    VStack(alignment: .leading, spacing: 12) {
        FilterChipBar(
            options: [
                FilterChipOption(value: AccountProductFilter.all, label: "todos os anúncios", count: 60),
                FilterChipOption(value: .discountOnly, label: "só os que pedem desconto", count: 3, dotColor: .statusDecision)
            ],
            selection: $filter
        )
        FilterChipBar(
            options: [
                FilterChipOption(value: "atual", label: "preço atual", count: 7, dotColor: Color(hex: "#1A7F37")),
                FilterChipOption(value: "alto", label: "preço alto, venda lenta", count: 3, dotColor: Color(hex: "#FF4D00")),
                FilterChipOption(value: "baixo", label: "preço baixo", count: 2, dotColor: .blue),
                FilterChipOption(value: "todos", label: "todos", count: 12)
            ],
            selection: $smartPriceFilter
        )
    }
}
