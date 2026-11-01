import SwiftUI

/// Etiqueta acima do seletor de abas no detalhe da conta (no iPhone): em qual loja você está e
/// quantos produtos ela tem, publicados mais inativos. No iPhone o título da barra de navegação
/// some atrás dos botões (fila, recarregar, selecionar) — sem isto, nada na tela dizia de qual das
/// lojas era a lista.
///
/// No coral da marca, cheio, com o texto escuro por cima: chama atenção sem usar uma cor que já
/// tem significado de status no app (laranja é desconto pendente, verde é deu certo, vermelho é
/// erro). Limitada a `.xLarge`, como as outras cápsulas: no `.xxxLarge` que o app força, "loja
/// Antônia · 1.842 produtos" passava da largura do iPhone.
struct StoreBadge: View {
    let name: String
    /// `nil` enquanto ainda não carregou.
    let publishedCount: Int?
    /// `nil` enquanto ainda não carregou.
    let inactiveCount: Int?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "storefront.fill")
            Text(StoreBadgeText.storeName(name))
                .fontWeight(.bold)
                .lineLimit(1)
            if let total = StoreBadgeText.totalProducts(published: publishedCount, inactive: inactiveCount) {
                Text("·")
                Text(StoreBadgeText.productCount(total))
                    .monospacedDigit()
                    .lineLimit(1)
                    // O nome encolhe (com reticências) antes da contagem.
                    .fixedSize()
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.onBrandCoral)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.brandCoral, in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            StoreBadgeText.accessibilityLabel(name: name, published: publishedCount, inactive: inactiveCount)
        )
        .accessibilityIdentifier("loja da conta")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        StoreBadge(name: "Mary", publishedCount: 1502, inactiveCount: 340)
        StoreBadge(name: "Antônia", publishedCount: 812, inactiveCount: nil)
        StoreBadge(name: "loja B", publishedCount: nil, inactiveCount: nil)
    }
    .padding()
}
