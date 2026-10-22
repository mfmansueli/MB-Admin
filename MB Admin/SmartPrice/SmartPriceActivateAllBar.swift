import SwiftUI

/// Barra de "ativar em N" da aba "sem preço esperto" no iPad/Mac, fora da seleção — o resumo em duas
/// linhas à esquerda ("6 produtos com preço atual" / "1 bloqueado fica de fora") e o botão à
/// direita, na mesma cápsula de vidro (e mesma largura) da `MegaphoneIdleBar` de "publicados".
///
/// No iPhone a barra de baixo é a do sistema, dividida com a lupa da busca minimizada — lá o botão
/// vira um item da toolbar e o resumo vai pro subtítulo da navegação (ver
/// `SmartPriceProductsListView`).
struct SmartPriceActivateAllBar: View {
    let activation: SmartPriceBulkActivation
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activation.title)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(activation.subtitle)
                    .font(.caption)
                    .foregroundStyle(.supportingText)
            }
            .lineLimit(1)
            .padding(.leading, 8)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            // Mesmo botão do "megafonar" da `MegaphoneIdleBar` — fora de uma toolbar, quem desenha
            // o vidro é o próprio estilo (ver `ProminentGlassButtonStyleModifier`).
            Button(action: onActivate) {
                Label(activation.buttonLabel, systemImage: "sparkles")
            }
            .buttonStyle(.tinted(.accentColor, size: 48))
            .disabled(activation.count == 0)
        }
        .padding(12)
        .glassSurface(in: .capsule)
        .frame(maxWidth: 660)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    let items = (0..<8).map { index in
        SmartPriceListItem(
            product: SmartPriceProduct(
                id: index,
                price: 199,
                minPrice: 159,
                maxPrice: 219,
                blocked: index == 3,
                smartPriceEnabled: false,
                statusText: "preço atual",
                statusColor: "#1A7F37",
                photoPublicID: nil
            ),
            matched: nil
        )
    }
    VStack {
        Spacer()
        SmartPriceActivateAllBar(
            activation: SmartPriceBulkActivation(items: items, filter: .current, activationStatuses: [:], isSearching: false)
        ) {}
        SmartPriceActivateAllBar(
            activation: SmartPriceBulkActivation(
                items: items,
                filter: .current,
                activationStatuses: [0: .succeeded, 1: .megaphoning, 2: .pending],
                isSearching: false
            )
        ) {}
    }
}
