import SwiftUI

/// Conteúdo da aba "sem preço esperto" da tela de detalhe da conta: lista os produtos que ainda não
/// têm o preço esperto ativado e deixa selecionar vários pra ativar de uma vez. A API de listagem
/// (`GET /api/smart_price/v2`) não devolve título nem link do anúncio — só id e preço — então nome
/// e link pra compartilhar vêm de cruzar o id com `account.runner.items` (os produtos publicados,
/// já carregados quando a tela de detalhe abre; ver `SmartPriceListItem`).
struct SmartPriceProductsListView: View {
    let account: AccountSession

    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var isConfirmingBulkActivate = false
    @State private var searchText = ""
    @State private var statusFilter: SmartPriceStatusFilter = .all
    @FocusState private var isSearchFocused: Bool

    private var loader: SmartPriceProductsLoader { account.smartPriceProductsLoader }

    var body: some View {
        VStack(spacing: 12) {
            switch loader.phase {
            // Itens persistidos de uma abertura anterior já chegam prontos no `init` do loader,
            // mas a fase continua `.idle` até `load()` ser chamado de novo — mesmo raciocínio de
            // `InactiveProductsListView`.
            case .idle where !loader.items.isEmpty:
                searchAndFilterBar
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
                        "tudo com preço esperto",
                        systemImage: "sparkles",
                        description: Text("não há produtos sem preço esperto nessa loja agora.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    searchAndFilterBar
                    selectionBar
                    list
                }
            case .failed(let message):
                ContentUnavailableView(
                    "não deu pra carregar",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxHeight: .infinity)
                Button("tentar de novo") { loader.load() }
                    .buttonStyle(.bordered)
            }
        }
        // Só busca sozinho quando ainda não tem nada — nem carregado agora, nem persistido de uma
        // abertura anterior do app — e só quando essa aba é de fato exibida.
        .task {
            guard loader.items.isEmpty, loader.phase == .idle else { return }
            loader.load()
        }
    }

    private var searchAndFilterBar: some View {
        HStack(spacing: 12) {
            SearchField(placeholder: "buscar por título", text: $searchText, isFocused: $isSearchFocused)
                .frame(maxWidth: .infinity)
            statusFilterPicker
        }
        .padding(.horizontal, 20)
    }

    private var statusFilterPicker: some View {
        Menu {
            Picker("filtro", selection: $statusFilter) {
                ForEach(SmartPriceStatusFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                // Tamanho mínimo fixo — mesmo raciocínio de `AccountPublishedTabView.filterPicker`:
                // sem isso, trocar pro rótulo mais longo ("preço alto, venda lenta") empurrava o
                // campo de busca ao lado no meio da animação de seleção.
                Text(statusFilter.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 90, minHeight: 32)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
    }

    /// Título e link de cada produto vêm de `account.runner.items` (a aba "publicados"), cruzado
    /// pelo id — ver comentário no topo do arquivo.
    private var titlesByID: [Int: EnjoeiProduct] {
        Dictionary(uniqueKeysWithValues: account.runner.items.map { ($0.product.id, $0.product) })
    }

    private var displayItems: [SmartPriceListItem] {
        let titles = titlesByID
        return loader.items.map { SmartPriceListItem(product: $0, matched: titles[$0.id]) }
    }

    /// Só o filtro de status ("todos"/"preço atual"/"preço alto, venda lenta"/"preço baixo") — a
    /// busca por título entra depois, em `filteredItems`. "Selecionar todos" considera o resultado
    /// final dos dois juntos (`selectableItems`, montado a partir de `filteredItems`).
    private var statusFilteredItems: [SmartPriceListItem] {
        guard statusFilter != .all else { return displayItems }
        return displayItems.filter { statusFilter.matches($0.product) }
    }

    private var filteredItems: [SmartPriceListItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return statusFilteredItems }
        return statusFilteredItems.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Só os itens não bloqueados entram na seleção — um item `blocked` não aceita a ação de
    /// ativar, então nem "selecionar todos" nem o toque na linha deixam marcá-lo (mesma checagem em
    /// `SmartPriceProductRowView`).
    private var selectableItems: [SmartPriceListItem] {
        filteredItems.filter { !$0.product.blocked }
    }

    private var selectionBar: some View {
        SelectionToggleBar(
            isSelecting: $isSelecting,
            hasItems: !selectableItems.isEmpty,
            isAllSelected: isAllSelectableSelected,
            hasSelection: !selectedIDs.isEmpty,
            onToggleSelecting: {
                isSelecting.toggle()
                if !isSelecting { selectedIDs.removeAll() }
            },
            onToggleSelectAll: { toggleSelectAll() }
        ) {
            BulkConfirmButton(
                systemImage: "sparkles",
                tint: .accentColor,
                label: "ativar preço esperto",
                accessibilityLabel: "ativar preço esperto em \(selectedIDs.count) produtos"
            ) {
                isConfirmingBulkActivate = true
            }
        }
        .padding(.horizontal, 20)
        .confirmationDialog(
            "aplicar preço esperto em \(selectedIDs.count) produtos?",
            isPresented: $isConfirmingBulkActivate,
            titleVisibility: .visible
        ) {
            Button("aplicar") { ativarSelecionados() }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("cada anúncio selecionado é ativado um de cada vez, com um intervalo entre um e o próximo — acompanhe o andamento pelo ícone de cada linha.")
        }
    }

    private var isAllSelectableSelected: Bool {
        !selectableItems.isEmpty && selectableItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelectAll() {
        let ids = selectableItems.map(\.id)
        if isAllSelectableSelected {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    @ViewBuilder
    private var list: some View {
        if filteredItems.isEmpty {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "nenhum produto nesse filtro",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("troque o filtro pra ver outros produtos.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            }
        } else {
            List(filteredItems) { item in
                SmartPriceProductRowView(
                    item: item,
                    loader: loader,
                    isSelecting: isSelecting,
                    isSelected: selectedIDs.contains(item.id),
                    onToggleSelection: { toggleSelection(item: item) }
                )
            }
            .listStyle(.plain)
        }
    }

    private func toggleSelection(item: SmartPriceListItem) {
        guard !item.product.blocked else { return }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func ativarSelecionados() {
        loader.activate(productIDs: Array(selectedIDs))
        selectedIDs.removeAll()
        isSelecting = false
    }
}
