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
    @FocusState private var isSearchFocused: Bool
    @Environment(AccountsStore.self) private var accountsStore

    private var loader: InactiveProductsLoader { account.inactiveProductsLoader }

    /// Ação escolhida pro botão de confirmar da seleção múltipla — repostar (cria de novo, sem
    /// mexer no status de inativo) ou ativar (volta o mesmo anúncio pra vitrine de publicados).
    private enum BulkAction: CaseIterable {
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
            guard loader.items.isEmpty, loader.phase == .idle else { return }
            loader.load()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("buscar por título", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .padding(.horizontal, 20)
        .contentShape(.rect)
        .onTapGesture { isSearchFocused = true }
    }

    private var filteredItems: [InactiveProduct] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return loader.items }
        return loader.items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var selectionBar: some View {
        HStack(spacing: 6) {
            Button(isSelecting ? "cancelar seleção" : "selecionar") {
                isSelecting.toggle()
                if !isSelecting {
                    selectedIDs.removeAll()
                    bulkAction = .repost
                }
            }
            .buttonStyle(.bordered)

            if isSelecting, !filteredItems.isEmpty {
                Button(isAllFilteredSelected ? "desmarcar todos" : "selecionar todos") {
                    toggleSelectAll()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if isSelecting, !selectedIDs.isEmpty {
                bulkActionSelector
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

    /// Seletor repostar/ativar + botão de confirmar — mesmo padrão da seleção múltipla em
    /// "publicados" (`AccountDetailView.bulkActionSelector`).
    private var bulkActionSelector: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("ação", selection: $bulkAction) {
                    ForEach(BulkAction.allCases, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(bulkAction.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }

            Button {
                switch bulkAction {
                case .repost: isConfirmingBulkRepost = true
                case .activate: isConfirmingBulkActivate = true
                }
            } label: {
                Image(systemName: bulkAction.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(bulkAction.label) \(selectedIDs.count) produtos")
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
