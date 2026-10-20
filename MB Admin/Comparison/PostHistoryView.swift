import SwiftUI

/// Tela de histórico: tudo que já passou pela fila de ações e terminou, com sucesso ou erro —
/// diferente de `PostQueueView`, que só mostra o que está pendente ou em andamento agora. Aberta a
/// partir da toolbar da fila de ações.
struct PostHistoryView: View {
    let postQueue: PostQueue

    @State private var isConfirmingClear = false
    @State private var searchText = ""
    @State private var kindFilter: PostQueueItem.Kind?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if postQueue.history.isEmpty {
                    ContentUnavailableView(
                        "nenhuma ação no histórico ainda",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("toda ação da fila (postar, repostar, apagar, inativar ou ativar) fica registrada aqui depois de terminar.")
                    )
                } else {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            SearchField(placeholder: "buscar por título", text: $searchText, isFocused: $isSearchFocused)
                                .frame(maxWidth: .infinity)
                            kindFilterMenu
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        if filteredHistory.isEmpty {
                            emptyFilteredState
                        } else {
                            // `LazyVStack` em vez de `List`: mesmo raciocínio de
                            // `AccountPublishedTabView.productList` — no idiom otimizado do Mac
                            // Catalyst, `List` vira `NSTableView`, caro pra reconstruir do zero.
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredHistory) { entry in
                                        PostHistoryRowView(entry: entry)
                                        if entry.id != filteredHistory.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("histórico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Mesmo `.fixedSize()` de `PostQueueView` — sem isso, o botão trunca no Mac
                    // (idiom otimizado).
                    Button("fechar") { dismiss() }
                        .fixedSize()
                }
                if !postQueue.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("limpar histórico", role: .destructive) {
                            isConfirmingClear = true
                        }
                        .fixedSize()
                    }
                }
            }
            .confirmationDialog(
                "limpar todo o histórico?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("limpar histórico", role: .destructive) {
                    postQueue.clearHistory()
                }
                Button("cancelar", role: .cancel) {}
            } message: {
                Text("remove todo o registro de ações já concluídas — não afeta a fila em andamento.")
            }
        }
    }

    private var filteredHistory: [PostHistoryEntry] {
        var entries = postQueue.history
        if let kindFilter {
            entries = entries.filter { $0.kind == kindFilter }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.product.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Busca sem resultado tem sua própria tela padrão do sistema; filtro por tipo sem resultado
    /// (com ou sem busca junto) usa uma mensagem genérica, já que `ContentUnavailableView.search`
    /// é especificamente sobre texto digitado.
    @ViewBuilder
    private var emptyFilteredState: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView(
                "nenhuma ação desse tipo no histórico",
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    /// Filtro por tipo de ação — "todas as ações" (`nil`) ou um `PostQueueItem.Kind` específico.
    private var kindFilterMenu: some View {
        Menu {
            Picker("tipo de ação", selection: $kindFilter) {
                Text(Self.kindFilterLabel(nil)).tag(PostQueueItem.Kind?.none)
                ForEach(PostQueueItem.Kind.allCases, id: \.self) { kind in
                    Text(Self.kindFilterLabel(kind)).tag(PostQueueItem.Kind?.some(kind))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                // Mesmo tamanho mínimo fixo do filtro de "publicados" (`AccountDetailView`) — sem
                // isso, trocar entre rótulos de tamanhos bem diferentes ("todas as ações" vs.
                // "ativar") faz o menu (e o campo de busca ao lado) pularem de tamanho no meio da
                // animação de seleção.
                Text(Self.kindFilterLabel(kindFilter))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 100, minHeight: 32)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
    }

    private static func kindFilterLabel(_ kind: PostQueueItem.Kind?) -> String {
        switch kind {
        case nil: "todas as ações"
        case .post: "postar/repostar"
        case .delete: "apagar"
        case .inactivate: "inativar"
        case .activate: "ativar"
        }
    }
}

#Preview {
    PostHistoryView(postQueue: PostQueue(poster: CrossAccountPoster(), accountsProvider: { [] }))
}
