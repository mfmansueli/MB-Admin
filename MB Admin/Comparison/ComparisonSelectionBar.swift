import SwiftUI

/// A barra de baixo da seleção no resultado da comparação: mandar os possivelmente ausentes pra
/// fila (postar na outra loja) e/ou apagar os anúncios a mais dos repetidos marcados (cada grupo
/// fica com o anúncio de "manter"). Cada botão só aparece quando a lista na tela tem algo daquele
/// tipo pra marcar; lado a lado, ou um embaixo do outro com letra grande.
struct ComparisonSelectionBar: View {
    var showsPost: Bool
    var postCount: Int
    var showsDelete: Bool
    /// Anúncios que vão pra fila pra serem apagados (não grupos).
    var deleteCount: Int
    var onPost: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 8) { buttons }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var buttons: some View {
        if showsPost {
            Button(action: onPost) {
                Label(postCount == 0 ? "adicionar à fila" : "adicionar \(postCount) à fila", systemImage: "paperplane.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tinted(.accentColor, size: 50))
            .disabled(postCount == 0)
        }
        if showsDelete {
            Button(action: onDelete) {
                Label(deleteLabel, systemImage: "trash.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tinted(.statusFailure, size: 50))
            .disabled(deleteCount == 0)
            .accessibilityIdentifier("deleteDuplicates")
        }
    }

    private var deleteLabel: String {
        switch deleteCount {
        case 0: "apagar repetidos"
        case 1: "apagar 1 repetido"
        default: "apagar \(deleteCount) repetidos"
        }
    }
}
