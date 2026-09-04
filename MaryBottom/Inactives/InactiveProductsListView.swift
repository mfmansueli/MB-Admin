import SwiftUI

/// Conteúdo da aba "inativos" da tela de detalhe da conta: lista os produtos inativos da própria
/// loja e deixa selecionar vários pra repostar (cria de novo) ou ativar (volta o mesmo anúncio)
/// de uma vez, entrando na mesma fila de ações usada pela comparação entre contas — aqui origem e
/// destino são sempre a própria conta.
struct InactiveProductsListView: View {
    let account: AccountSession

    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var bulkAction: BulkAction = .repost
    @State private var isConfirmingBulkRepost = false
    @State private var isConfirmingBulkActivate = false
    @State private var searchText = ""
    /// Cache de `filteredItems` (ver `recomputeFilteredItems`) — sem isso, cada leitura (lista,
    /// "selecionar todos", contagem) refiltrava a lista inteira do zero, várias vezes por
    /// digitação, numa loja com muitos produtos inativos.
    @State private var filteredItems: [InactiveProduct] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @Environment(AccountsStore.self) private var accountsStore

    private var loader: InactiveProductsLoader { account.inactiveProductsLoader }

    /// Ação escolhida pro botão de confirmar da seleção múltipla — repostar (cria de novo, sem
    /// mexer no status de inativo) ou ativar (volta o mesmo anúncio pra vitrine de publicados).
    private enum BulkAction: BulkActionOption {
        case repost
        case activate

        var label: String {
            switch self {
            case .repost: "repostar"
            case .activate: "ativar"
            }
        }

        var systemImage: String {
            switch self {
            case .repost: "doc.on.doc.fill"
            case .activate: "tray.and.arrow.up.fill"
            }
        }

        var tint: Color { .accentColor }
    }

    var body: some View {
        VStack(spacing: 12) {
            switch loader.phase {
            // Itens persistidos de uma abertura anterior já chegam prontos no `init` do loader,
            // mas a fase continua `.idle` até `load()` ser chamado de novo — sem esse caso, a tela
            // ficava presa num spinner pra sempre nesse cenário (o `.task` abaixo, corretamente,
            // não chama `load()` de novo só porque já tem itens).
            case .idle where !loader.items.isEmpty:
                searchField
                selectionBar
                list
            case .idle:
                Spacer()
                ProgressView()
                    .frame(maxWidth: .infinity)
                Spacer()
            case .loadingPage(let page, let total) where loader.items.isEmpty:
                Spacer()
                ProgressView("carregando página \(page) de \(total)…")
                    .frame(maxWidth: .infinity)
                Spacer()
            case .loadingPage, .finished:
                if loader.items.isEmpty {
                    ContentUnavailableView(
                        "nenhum produto inativo",
                        systemImage: "archivebox",
                        description: Text("não há produtos inativos nessa loja agora.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    searchField
                    selectionBar
                    list
                }
            case .failed(let message):
                ContentUnavailableView(
                    "não deu pra carregar os inativos",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxHeight: .infinity)
                Button("tentar de novo") { loader.load() }
                    .buttonStyle(.bordered)
            }
        }
        // Só busca sozinho quando ainda não tem nada — nem carregado agora, nem persistido de uma
        // abertura anterior do app — e só quando essa aba é de fato exibida (a view nem é
        // construída enquanto "publicados" estiver selecionado).
        .task {
            if loader.items.isEmpty, loader.phase == .idle {
                loader.load()
            }
            recomputeFilteredItems()
        }
        // `loader.items` muda várias vezes durante o carregamento (uma página de cada vez) — cada
        // mudança recalcula o filtro uma vez só, em vez de a cada leitura de `filteredItems`.
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

    /// Sem busca, mostra `loader.items` direto (já está em memória, completo — sem motivo pra
    /// consultar o SwiftData de novo). Com busca, delega pro loader (que consulta o SwiftData com
    /// `#Predicate` + `fetchLimit` — ver `InactiveProductsLoader.search(matching:)`), em vez de
    /// filtrar `loader.items` inteiro em Swift a cada tecla.
    private func recomputeFilteredItems() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredItems = trimmed.isEmpty ? loader.items : loader.search(matching: trimmed)
    }

    private var searchField: some View {
        SearchField(placeholder: "buscar por título", text: $searchText, isFocused: $isSearchFocused)
            .padding(.horizontal, 20)
    }

    private var selectionBar: some View {
        SelectionToggleBar(
            isSelecting: $isSelecting,
            hasItems: !filteredItems.isEmpty,
            isAllSelected: isAllFilteredSelected,
            hasSelection: !selectedIDs.isEmpty,
            onToggleSelecting: {
                isSelecting.toggle()
                if !isSelecting {
                    selectedIDs.removeAll()
                    bulkAction = .repost
                }
            },
            onToggleSelectAll: { toggleSelectAll() }
        ) {
            BulkActionSelector(selection: $bulkAction, selectedCount: selectedIDs.count) {
                switch bulkAction {
                case .repost: isConfirmingBulkRepost = true
                case .activate: isConfirmingBulkActivate = true
                }
            }
        }
        .padding(.horizontal, 20)
        .confirmationDialog(
            "repostar \(selectedIDs.count) produtos?",
            isPresented: $isConfirmingBulkRepost,
            titleVisibility: .visible
        ) {
            Button("repostar") { repostarSelecionados() }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("entra na fila de ações, reaproveitando título, descrição, preço e fotos de cada um — acompanhe o andamento por lá.")
        }
        .confirmationDialog(
            "ativar \(selectedIDs.count) produtos de novo?",
            isPresented: $isConfirmingBulkActivate,
            titleVisibility: .visible
        ) {
            Button("ativar") { ativarSelecionados() }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("cada anúncio selecionado entra na fila de ações e volta pra vitrine de publicados.")
        }
    }

    /// Considera só os itens que a busca deixa passar — "selecionar todos" com um texto digitado
    /// pega só o que está visível na lista, não a loja inteira por trás do filtro.
    private var isAllFilteredSelected: Bool {
        !filteredItems.isEmpty && filteredItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelectAll() {
        let filteredIDs = filteredItems.map(\.id)
        if isAllFilteredSelected {
            selectedIDs.subtract(filteredIDs)
        } else {
            selectedIDs.formUnion(filteredIDs)
        }
    }

    @ViewBuilder
    private var list: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxHeight: .infinity)
        } else {
            List(filteredItems) { product in
                InactiveProductRowView(
                    product: product,
                    account: account,
                    isSelecting: isSelecting,
                    isSelected: selectedIDs.contains(product.id),
                    onToggleSelection: { toggleSelection(productID: product.id) }
                )
            }
            .listStyle(.plain)
        }
    }

    private func toggleSelection(productID: Int) {
        if selectedIDs.contains(productID) {
            selectedIDs.remove(productID)
        } else {
            selectedIDs.insert(productID)
        }
    }

    private func repostarSelecionados() {
        for product in loader.items where selectedIDs.contains(product.id) {
            accountsStore.postQueue.enqueue(product: placeholder(for: product), source: account, destination: account)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    private func ativarSelecionados() {
        for product in loader.items where selectedIDs.contains(product.id) {
            accountsStore.postQueue.enqueueActivate(product: placeholder(for: product), account: account)
        }
        selectedIDs.removeAll()
        isSelecting = false
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
