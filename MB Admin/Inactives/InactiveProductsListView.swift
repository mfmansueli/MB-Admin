import SwiftUI

/// Conteúdo da aba "inativos" da tela de detalhe da conta: lista os produtos inativos da própria
/// loja e deixa selecionar vários pra repostar (cria de novo), ativar (volta o mesmo anúncio) ou
/// apagar de vez, entrando na mesma fila de ações usada pela comparação entre contas — aqui origem
/// e destino são sempre a própria conta.
///
/// Mesmo padrão da aba "publicados": "selecionar" na barra de cima; selecionando, o título conta a
/// seleção (`AccountDetailView`, dona desse estado — por isso as `@Binding`), "selecionar tudo" e o
/// "concluir" ficam em cima, e as ações numa barra de vidro embaixo, cada uma confirmada por alerta.
/// A busca fica na barra do sistema (no iPhone, a lupa embaixo) e some durante a seleção.
struct InactiveProductsListView: View {
    let account: AccountSession
    @Binding var searchText: String
    @Binding var isSelecting: Bool
    @Binding var selectedIDs: Set<Int>

    @State private var pendingBulkAction: InactiveBulkAction?
    /// Cache de `filteredItems` (ver `recomputeFilteredItems`) — sem isso, cada leitura (lista,
    /// "todos", contagem) refiltrava a lista inteira do zero, várias vezes por digitação, numa loja
    /// com muitos produtos inativos.
    @State private var filteredItems: [InactiveProduct] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @Environment(AccountsStore.self) private var accountsStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var loader: InactiveProductsLoader { account.inactiveProductsLoader }
    private var isCompact: Bool { horizontalSizeClass != .regular }

    var body: some View {
        content
            .toolbar { toolbarContent }
            // Mesmo esquema da aba "publicados": a busca só existe fora da seleção, num fundo vazio
            // (pôr/tirar `.searchable` da própria lista trocaria a identidade dela).
            .background {
                if !isSelecting {
                    Color.clear
                        .searchable(text: $searchText, prompt: "buscar por título")
                        .modifier(MinimizedSearchOnCompact(isCompact: isCompact))
                }
            }
            .floatingBottomBar {
                if isSelecting {
                    SelectionActionBar(actions: InactiveBulkAction.allCases, isEnabled: !selectedIDs.isEmpty) { action in
                        pendingBulkAction = action
                    }
                }
            }
            // Selecionando, sair pela seta de voltar largaria a seleção pela metade.
            .navigationBarBackButtonHidden(isSelecting)
            .toolbar(isSelecting ? .hidden : .automatic, for: .bottomBar)
            .alert(
                pendingBulkAction?.confirmationTitle(count: selectedLiveProducts.count) ?? "",
                isPresented: Binding(
                    get: { pendingBulkAction != nil },
                    set: { if !$0 { pendingBulkAction = nil } }
                ),
                presenting: pendingBulkAction
            ) { action in
                Button("cancelar", role: .cancel) {}
                Button(action.confirmationButtonLabel, role: action.isDestructive ? .destructive : nil) {
                    perform(action)
                }
            } message: { action in
                Text(action.confirmationMessage)
            }
            // `initial: true` cobre tanto a primeira vez que esta view aparece quanto cada troca de
            // conta na barra lateral mantendo a mesma aba selecionada — sem `.id(account.id)` (ver
            // `AccountDetailView`), é o único gatilho que sobra pra carregar a conta nova. Busca e
            // seleção quem zera é `AccountDetailView.loadState`, dona delas.
            .onChange(of: account.id, initial: true) { _, _ in
                pendingBulkAction = nil
                searchDebounceTask?.cancel()
                searchDebounceTask = nil
                if loader.items.isEmpty, loader.phase == .idle {
                    loader.load()
                }
                recomputeFilteredItems()
            }
            // `loader.items` muda várias vezes durante o carregamento (uma página de cada vez) —
            // cada mudança recalcula o filtro uma vez só, em vez de a cada leitura.
            .onChange(of: loader.items) { _, _ in recomputeFilteredItems() }
            // Debounce: espera a digitação parar por 200ms antes de refiltrar, em vez de refazer o
            // filtro (potencialmente sobre centenas de produtos) a cada tecla.
            .onChange(of: searchText) { _, _ in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    recomputeFilteredItems()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch loader.phase {
        // Itens persistidos de uma abertura anterior já chegam prontos no `init` do loader, mas a
        // fase continua `.idle` até `load()` ser chamado de novo — sem esse caso, a tela ficava
        // presa num spinner pra sempre nesse cenário.
        case .idle where !loader.items.isEmpty:
            list
        case .idle:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loadingPage(let page, let total) where loader.items.isEmpty:
            ProgressView("carregando página \(page) de \(total)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loadingPage, .finished:
            if loader.items.isEmpty {
                ContentUnavailableView(
                    "nenhum produto inativo",
                    systemImage: "archivebox",
                    description: Text("não há produtos inativos nessa loja agora.")
                )
                .frame(maxHeight: .infinity)
            } else {
                list
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("não deu pra carregar os inativos", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("tentar de novo") { loader.load() }
                    .glassButtonStyle()
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Sem busca, mostra `loader.items` direto (já está em memória, completo — sem motivo pra
    /// consultar o SwiftData de novo). Com busca, delega pro loader (que consulta o SwiftData com
    /// `#Predicate` + `fetchLimit` — ver `InactiveProductsLoader.search(matching:)`), em vez de
    /// filtrar `loader.items` inteiro em Swift a cada tecla.
    private func recomputeFilteredItems() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredItems = trimmed.isEmpty ? loader.items : loader.search(matching: trimmed)
    }

    @ViewBuilder
    private var list: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxHeight: .infinity)
        } else {
            // `LazyVStack` em vez de `List`: mesmo raciocínio de `AccountPublishedTabView.productList`
            // — no idiom otimizado do Mac Catalyst, `List` vira `NSTableView`, caro pra reconstruir
            // do zero a cada troca de conta.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { product in
                        InactiveProductRowView(
                            product: product,
                            account: account,
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(product.id),
                            isCompact: isCompact,
                            onToggleSelection: { toggleSelection(productID: product.id) }
                        )
                        if product.id != filteredItems.last?.id {
                            Divider()
                                .padding(.leading, (isCompact ? 16 : 24) + 64 + 12 + (isSelecting ? 36 : 0))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(isAllFilteredSelected ? "desmarcar tudo" : "selecionar tudo") {
                    selectedIDs = PublishedProductSections.togglingAll(filteredItems.map(\.id), in: selectedIDs)
                }
                .fixedSize()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    endSelection()
                } label: {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.onTint)
                }
                .prominentGlassButtonStyle()
                .accessibilityLabel("concluir seleção")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("selecionar") {
                    // No Mac o botão nunca fica desabilitado (ver `ToolbarItemDisabled`).
                    guard !filteredItems.isEmpty else { return }
                    isSelecting = true
                }
                .fixedSize()
                .toolbarItemDisabled(filteredItems.isEmpty)
            }
        }
    }

    // MARK: - Seleção

    /// Considera só os itens que a busca deixa passar — "selecionar tudo" com um texto digitado pega só o que
    /// está visível na lista, não a loja inteira por trás do filtro.
    private var isAllFilteredSelected: Bool {
        !filteredItems.isEmpty && filteredItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelection(productID: Int) {
        if selectedIDs.contains(productID) {
            selectedIDs.remove(productID)
        } else {
            selectedIDs.insert(productID)
        }
    }

    private func endSelection() {
        selectedIDs.removeAll()
        isSelecting = false
    }

    private func perform(_ action: InactiveBulkAction) {
        for product in selectedLiveProducts {
            let placeholder = placeholder(for: product)
            switch action {
            case .repost:
                accountsStore.postQueue.enqueue(product: placeholder, source: account, destination: account)
            case .activate:
                accountsStore.postQueue.enqueueActivate(product: placeholder, account: account)
            case .delete:
                // Mesma fila de ações usada pelo "apagar produto" de cada linha (e pela aba de
                // publicados).
                accountsStore.postQueue.enqueueDelete(product: placeholder, account: account)
            }
        }
        endSelection()
    }

    /// Os selecionados que ainda existem no enjoei — um já apagado nesta sessão continua na lista
    /// (marcado, até o próximo carregamento), mas qualquer ação nele só falharia na fila.
    private var selectedLiveProducts: [InactiveProduct] {
        loader.items.filter {
            selectedIDs.contains($0.id) && account.runner.deleteStatuses[$0.id] != .succeeded
        }
    }

    /// A fila só usa `id` (pra ler o template de novo), `title` e `photoPublicID` (pra exibir) — o
    /// resto do `EnjoeiProduct` não importa aqui, então fica com valores neutros.
    private func placeholder(for product: InactiveProduct) -> EnjoeiProduct {
        EnjoeiProduct(
            id: product.id,
            title: product.title,
            path: product.path,
            photoPublicID: product.photoPublicID,
            currentPrice: product.price,
            originalPrice: product.price
        )
    }
}
