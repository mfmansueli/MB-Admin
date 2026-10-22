import SwiftUI

/// Conteúdo da aba "sem preço esperto" da tela de detalhe da conta: lista os produtos que ainda não
/// têm o preço esperto ativado e deixa selecionar vários pra ativar de uma vez. A API de listagem
/// (`GET /api/smart_price/v2`) não devolve título nem link do anúncio — só id e preço — então nome
/// e link pra compartilhar vêm de cruzar o id com `account.runner.items` (os produtos publicados,
/// já carregados quando a tela de detalhe abre; ver `SmartPriceListItem`).
///
/// Mesmo padrão das abas "publicados"/"inativos": filtro e "selecionar" na barra de cima, busca na
/// barra do sistema, e selecionando, o título conta a seleção (`AccountDetailView`, dona desse
/// estado) e a ação — uma só, ativar — fica num botão embaixo.
struct SmartPriceProductsListView: View {
    let account: AccountSession
    @Binding var searchText: String
    @Binding var isSelecting: Bool
    @Binding var selectedIDs: Set<Int>

    @State private var isConfirmingBulkActivate = false
    @State private var statusFilter: SmartPriceStatusFilter = .all
    /// Cache de `filteredItems`/`selectableItems` (ver `recomputeFilteredItems`) — antes disso, uma
    /// cadeia inteira (`titlesByID` → `displayItems` → `statusFilteredItems` → `filteredItems` →
    /// `selectableItems`) era refeita do zero a cada leitura, várias vezes por render, numa loja
    /// com muitos produtos.
    @State private var filteredItems: [SmartPriceListItem] = []
    @State private var selectableItems: [SmartPriceListItem] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var loader: SmartPriceProductsLoader { account.smartPriceProductsLoader }
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
                    activateBar
                }
            }
            // Selecionando, sair pela seta de voltar largaria a seleção pela metade.
            .navigationBarBackButtonHidden(isSelecting)
            .toolbar(isSelecting ? .hidden : .automatic, for: .bottomBar)
            .alert(
                "aplicar preço esperto em \(selectedIDs.count == 1 ? "1 produto" : "\(selectedIDs.count) produtos")?",
                isPresented: $isConfirmingBulkActivate
            ) {
                Button("cancelar", role: .cancel) {}
                Button("aplicar") { ativarSelecionados() }
            } message: {
                Text(
                    "cada anúncio selecionado é ativado um de cada vez, com um intervalo entre um e o próximo — "
                        + "acompanhe o andamento pelo ícone de cada linha."
                )
            }
            // `initial: true` cobre tanto a primeira vez que esta view aparece quanto cada troca de
            // conta na barra lateral mantendo a mesma aba selecionada — sem `.id(account.id)` (ver
            // `AccountDetailView`), é o único gatilho que sobra pra carregar a conta nova e zerar o
            // filtro. Busca e seleção quem zera é `AccountDetailView.loadState`, dona delas.
            .onChange(of: account.id, initial: true) { _, _ in
                isConfirmingBulkActivate = false
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
            // De propósito NÃO é `account.runner.items` direto: aquele array muda uma vez por
            // produto megafonado (até 1500+ vezes por rodada), e `Equatable` de `[MegaphoneItem]`
            // compara campo a campo (incluindo strings) — um `onChange` nele custa O(catálogo) a cada
            // produto processado, mesmo bug que travava a aba "publicados" (ver o comentário lá em
            // `AccountPublishedTabView.swift`). `progressSnapshot` é a struct pequena e barata que
            // já existe exatamente pra isso, atualizada em lote, não a cada item.
            .onChange(of: loader.items) { _, _ in recomputeFilteredItems() }
            .onChange(of: account.runner.progressSnapshot) { _, _ in
                loader.refreshPersistedTitles()
                recomputeFilteredItems()
            }
            .onChange(of: statusFilter) { _, _ in
                // Trocar de filtro com itens marcados deixaria parte da seleção escondida, mas
                // ainda sendo ativada.
                selectedIDs.removeAll()
                recomputeFilteredItems()
            }
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

    @ViewBuilder
    private var content: some View {
        switch loader.phase {
        // Itens persistidos de uma abertura anterior já chegam prontos no `init` do loader, mas a
        // fase continua `.idle` até `load()` ser chamado de novo — mesmo raciocínio de
        // `InactiveProductsListView`.
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
                    "tudo com preço esperto",
                    systemImage: "sparkles",
                    description: Text("não há produtos sem preço esperto nessa loja agora.")
                )
                .frame(maxHeight: .infinity)
            } else {
                list
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("não deu pra carregar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("tentar de novo") { loader.load() }
                    .glassButtonStyle()
            }
            .frame(maxHeight: .infinity)
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
        // ativar, então nem "selecionar tudo" nem o toque na linha deixam marcá-lo (mesma checagem em
        // `SmartPriceProductRowView`).
        selectableItems = items.filter { !$0.product.blocked }
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
                            isCompact: isCompact,
                            onToggleSelection: { toggleSelection(item: item) }
                        )
                        if item.id != filteredItems.last?.id {
                            Divider()
                                .padding(.leading, (isCompact ? 16 : 24) + 64 + 12 + (isSelecting ? 36 : 0))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Barras

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(isAllSelectableSelected ? "desmarcar tudo" : "selecionar tudo") {
                    selectedIDs = PublishedProductSections.togglingAll(selectableItems.map(\.id), in: selectedIDs)
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
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("selecionar") {
                    // No Mac o botão nunca fica desabilitado (ver `ToolbarItemDisabled`).
                    guard !selectableItems.isEmpty else { return }
                    isSelecting = true
                }
                .fixedSize()
                .toolbarItemDisabled(selectableItems.isEmpty)
            }
        }
    }

    /// Mesmo padrão do filtro de "publicados": no iPhone, o "recarregar" mora aqui dentro (não cabe
    /// um botão à parte na barra de cima); o ícone não muda com o filtro ligado no Mac (ver
    /// `AccountPublishedTabView.filterSymbol`).
    private var filterMenu: some View {
        Menu {
            Picker("filtro", selection: $statusFilter) {
                ForEach(SmartPriceStatusFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.inline)
            if isCompact {
                Section {
                    Button {
                        account.reloadAllProducts()
                    } label: {
                        Label("recarregar produtos", systemImage: "arrow.clockwise")
                    }
                    .disabled(account.runner.isRunning)
                }
            }
        } label: {
            Label("filtrar produtos", systemImage: filterSymbol)
        }
    }

    private var filterSymbol: String {
        #if targetEnvironment(macCatalyst)
        "line.3.horizontal.decrease"
        #else
        statusFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
        #endif
    }

    private var activateBar: some View {
        Button {
            isConfirmingBulkActivate = true
        } label: {
            Label(
                selectedIDs.isEmpty ? "ativar preço esperto" : "ativar preço esperto em \(selectedIDs.count)",
                systemImage: "sparkles"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tinted(.accentColor, size: 50))
        .disabled(selectedIDs.isEmpty)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Seleção

    private var isAllSelectableSelected: Bool {
        !selectableItems.isEmpty && selectableItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelection(item: SmartPriceListItem) {
        guard !item.product.blocked else { return }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func endSelection() {
        selectedIDs.removeAll()
        isSelecting = false
    }

    private func ativarSelecionados() {
        loader.activate(productIDs: Array(selectedIDs))
        endSelection()
    }
}
