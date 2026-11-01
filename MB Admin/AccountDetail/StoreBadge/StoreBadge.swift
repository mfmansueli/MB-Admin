import SwiftUI

/// Etiqueta acima do seletor de abas no detalhe da conta (no iPhone): em qual loja você está e
/// quando o catálogo dela foi recarregado pela última vez (o toque em "recarregar produtos", ver
/// `AccountSession.lastCatalogRefresh`). No iPhone o título da barra de navegação some atrás dos
/// botões (fila, recarregar, selecionar) — sem isto, nada na tela dizia de qual das lojas era a
/// lista.
///
/// Antes mostrava quantos produtos a loja tinha (publicados mais inativos); trocado pela hora a
/// pedido do usuário — as quantidades já estão nas cápsulas de filtro e na aba "inativos".
///
/// No coral da marca, cheio, com o texto escuro por cima: chama atenção sem usar uma cor que já
/// tem significado de status no app (laranja é desconto pendente, verde é deu certo, vermelho é
/// erro). Limitada a `.xLarge`, como as outras cápsulas: no `.xxxLarge` que o app força, a
/// etiqueta passava da largura do iPhone.
struct StoreBadge: View {
    let name: String
    /// `nil` enquanto nunca recarregou.
    let refreshedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "storefront.fill")
            Text(StoreBadgeText.storeName(name))
                .fontWeight(.bold)
                .lineLimit(1)
            if let refreshedAt {
                Text("·")
                // O mesmo ícone do botão de recarregar, lá em cima — é ele que diz o que é a hora.
                Image(systemName: "arrow.clockwise")
                    .imageScale(.small)
                Text(StoreBadgeText.refreshTime(refreshedAt))
                    .monospacedDigit()
                    .lineLimit(1)
                    // O nome encolhe (com reticências) antes da hora.
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
        .accessibilityLabel(StoreBadgeText.accessibilityLabel(name: name, refreshedAt: refreshedAt))
        .accessibilityIdentifier("loja da conta")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        StoreBadge(name: "Mary", refreshedAt: .now)
        StoreBadge(name: "Antônia Fernandes da Silva", refreshedAt: .now.addingTimeInterval(-86_400 * 400))
        StoreBadge(name: "loja B", refreshedAt: nil)
    }
    .padding()
}
