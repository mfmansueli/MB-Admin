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
    /// Cache de `filteredItems`/`selectableItems` (ver `recomputeFilteredItems`) — antes disso, uma
    /// cadeia inteira (`titlesByID` → `displayItems` → `statusFilteredItems` → `filteredItems` →
    /// `selectableItems`) era refeita do zero a cada leitura, várias vezes por render, numa loja
    /// com muitos produtos.
    @State private var filteredItems: [SmartPriceListItem] = []
    @State private var selectableItems: [SmartPriceListItem] = []
    @State private var searchDebounceTask: Task<Void, Never>?
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
        // `initial: true` cobre tanto a primeira vez que esta view aparece quanto cada troca de
        // conta na barra lateral mantendo a mesma aba selecionada — sem `.id(account.id)` (esta
        // view não é mais destruída/reconstruída a cada troca de conta, ver `AccountDetailView`),
        // o switch/case em `AccountDetailView.body` só desmonta esta view quando a ABA muda, não
        // quando só a conta muda — por isso este `onChange` é o único gatilho que sobra pra zerar
        // busca/seleção/filtro antes que vazem de uma conta pra outra.
        .onChange(of: account.id, initial: true) { _, _ in
            isSelecting = false
            selectedIDs = []
            isConfirmingBulkActivate = false
            searchText = ""
            statusFilter = .all
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            if loader.items.isEmpty, loader.phase == .idle {
                loader.load()
            }
            loader.refreshPersistedTitles()
            recomputeFilteredItems()
        }
        // `loader.items` muda a cada página carregada; `account.runner.progressSnapshot` é quem
        // avisa que os publicados (título/link) chegaram ou mudaram — qualquer um dos dois
        // mudando recalcula o filtro uma vez só. Quando é o snapshot que muda, também conserta
        // (`refreshPersistedTitles`) os registros que ficaram com título vazio por terem sido
        // gravados antes da aba "publicados" responder.
        //
        // De propósito NÃO é `account.runner.items` direto: aquele array muda uma vez por produto
        // megafonado (até 1500+ vezes por rodada), e `Equatable` de `[MegaphoneItem]` compara
        // campo a campo (incluindo strings) — um `onChange` nele custa O(catálogo) a cada produto
        // processado, mesmo bug que travava a aba "publicados" (ver o comentário lá em
        // `AccountPublishedTabView.swift`), só que aqui só morde se esta aba ficar aberta enquanto
        // o megafone roda em segundo plano. `progressSnapshot` é a struct pequena e barata que já
        // existe exatamente pra isso, atualizada em lote (`progressSnapshotBatchSize`), não a cada
        // item.
        .onChange(of: loader.items) { _, _ in recomputeFilteredItems() }
        .onChange(of: account.runner.progressSnapshot) { _, _ in
            loader.refreshPersistedTitles()
            recomputeFilteredItems()
        }
        .onChange(of: statusFilter) { _, _ in recomputeFilteredItems() }
        // Debounce: espera a digitação parar por 200ms antes de refiltrar, em vez de refazer a
        // cadeia inteira (potencialmente sobre centenas de produtos) a cada tecla.
        .onChange(of: searchText) { _, _ in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                recomputeFilteredItems()
            }
        }
    }

    /// Sem busca, monta a partir de `loader.items` (já em memória, completo). Com busca, delega a
    /// parte de título pro loader (que consulta o SwiftData com `#Predicate` + `fetchLimit` — ver
    /// `SmartPriceProductsLoader.search(matching:)`), em vez de filtrar tudo em Swift a cada tecla.
    /// De um jeito ou de outro, ainda precisa cruzar com `account.runner.items` pra ter link/foto de
    /// verdade (a API de preço esperto não devolve isso — só o título fica persistido, ver
    /// `SmartPriceProductRecord`) e aplicar o filtro de status por cima.
    private func recomputeFilteredItems() {
        let titles = Dictionary(uniqueKeysWithValues: account.runner.items.map { ($0.product.id, $0.product) })
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseProducts = trimmed.isEmpty ? loader.items : loader.search(matching: trimmed)
        var items = baseProducts.map { SmartPriceListItem(product: $0, matched: titles[$0.id]) }
        if statusFilter != .all {
            items = items.filter { statusFilter.matches($0.product) }
        }
        filteredItems = items
        // Só os itens não bloqueados entram na seleção — um item `blocked` não aceita a ação de
        // ativar, então nem "selecionar todos" nem o toque na linha deixam marcá-lo (mesma checagem
        // em `SmartPriceProductRowView`).
        selectableItems = items.filter { !$0.product.blocked }
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
            // `LazyVStack` em vez de `List`: mesmo raciocínio de `AccountPublishedTabView.productList`
            // — no idiom otimizado do Mac Catalyst, `List` vira `NSTableView`, caro pra reconstruir
            // do zero a cada troca de conta.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        SmartPriceProductRowView(
                            item: item,
                            loader: loader,
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(item.id),
                            onToggleSelection: { toggleSelection(item: item) }
                        )
                        if item.id != filteredItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
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
