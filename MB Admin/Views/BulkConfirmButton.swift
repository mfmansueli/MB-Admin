import SwiftUI

/// Botão "confirmar" da seleção múltipla — ícone (e, opcionalmente, um texto ao lado) branco sobre
/// um fundo colorido (vidro líquido a partir do iOS/Mac Catalyst 26, cor sólida antes disso). Sem
/// `label`, vira um círculo só com o ícone — usado por `BulkActionSelector` (a ação já aparece no
/// menu ao lado, então o botão de confirmar não repete o texto). Com `label`, vira uma cápsula
/// ícone + texto — usado por telas com uma ação em massa só, sem menu de escolha (ex.:
/// `SmartPriceProductsListView`, "ativar preço esperto").
struct BulkConfirmButton: View {
    let systemImage: String
    let tint: Color
    var label: String?
    let accessibilityLabel: String
    let action: () -> Void

    init(
        systemImage: String,
        tint: Color,
        label: String? = nil,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let label {
                labeledIcon(label)
                    .modifier(BulkConfirmBackground(tint: tint, shape: .capsule))
            } else {
                icon
                    .modifier(BulkConfirmBackground(tint: tint, shape: .circle))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // Redimensionado explicitamente (em vez de só fixar a fonte) — sem isso, ícones mais largos
    // (ex.: `doc.on.doc.fill`, duas páginas sobrepostas) estouravam o círculo em vez de ficar
    // contidos nele.
    private var icon: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .frame(width: 38, height: 38)
    }

    private func labeledIcon(_ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(label)
        }
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .frame(height: 38)
        .padding(.horizontal, 14)
    }
}

/// O material "liquid glass" só existe a partir do iOS/Mac Catalyst 26 — mais velho que isso cai de
/// volta pro fundo colorido sólido de antes. Extraído de `BulkConfirmButton` pra não duplicar o
/// `#available` entre a variante só-ícone (círculo) e a variante ícone+texto (cápsula).
private struct BulkConfirmBackground: ViewModifier {
    let tint: Color
    let shape: AnyShape

    init(tint: Color, shape: some Shape) {
        self.tint = tint
        self.shape = AnyShape(shape)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content.background(tint, in: shape)
        }
    }
}
