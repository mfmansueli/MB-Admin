import SwiftUI

/// Resultado de uma comparação já carregada, em seções-cartão: mesmo produto, precisa revisar,
/// possivelmente ausentes em cada loja, não deu pra verificar e marcados como diferentes — com o
/// aviso de comparação incompleta no topo, o filtro na barra de cima, a busca (no iPhone, a lupa na
/// barra de baixo) e a seleção múltipla **só** dos possivelmente ausentes pra mandar pra fila de
/// ações. Quem chama passa `.id(result.id)`: cada comparação nova nasce com busca/filtro/seleção
/// zerados, mas uma revisão manual (mesmo `id`, `revision` nova) só atualiza as seções.
struct ComparisonResultView: View {
    let result: AccountComparisonResult
    let accountA: AccountSession
    let accountB: AccountSession
    let poster: CrossAccountPoster
    let postQueue: PostQueue
    var onDecide: (ComparisonDecision.Verdict, ProductMatch) -> Void = { _, _ in }
    var onUndo: (ProductMatch) -> Void = { _ in }
    var onRetry: () -> Void = {}

    @State private var resultFilter: ComparisonResultFilter = .all
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedProductIDs: Set<Int> = []
    /// Cache do filtro + busca (ver `recomputeFilteredItems`) — sem isso, o filtro rodava sobre os
    /// três resultados inteiros a cada leitura no `body`, várias vezes por render, numa comparação
    /// com muitos produtos. Mesmo raciocínio de `AccountPublishedTabView.sections`.
    @State private var filtered = ComparisonFilteredResult()
    @State private var searchDebounceTask: Task<Void, Never>?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass != .regular }

    var body: some View {
        resultList
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(isSelecting ? selectionTitle : "comparar produtos")
            .navigationSubtitleIfAvailable(subtitle)
            .toolbar { toolbarContent }
            // Mesmo esquema da aba "publicados": a busca só existe fora da seleção, num fundo vazio
            // (pôr/tirar `.searchable` da própria lista trocaria a identidade dela).
            .background {
                if !isSelecting {
                    Color.clear
                        .searchable(text: $searchText, prompt: "buscar produto")
                        .modifier(MinimizedSearchOnCompact(isCompact: isCompact))
                }
            }
            .floatingBottomBar {
                if isSelecting {
                    selectionBar
                }
            }
            .toolbar(isSelecting ? .hidden : .automatic, for: .bottomBar)
            .task { recomputeFilteredItems() }
            // Uma revisão manual recalcula o resultado com o mesmo `id` — só refiltra.
            .onChange(of: result.revision) { _, _ in recomputeFilteredItems() }
            .onChange(of: resultFilter) { _, _ in
                // Trocar de filtro com itens marcados deixaria parte da seleção escondida, mas
                // ainda indo pra fila.
                selectedProductIDs.removeAll()
                recomputeFilteredItems()
            }
            // Debounce: espera a digitação parar por 200ms antes de refiltrar, mesmo raciocínio de
            // `AccountPublishedTabView.searchText`.
            .onChange(of: searchText) { _, _ in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    recomputeFilteredItems()
                }
            }
    }

    private func recomputeFilteredItems() {
        filtered = ComparisonFilteredResult(result: result, filter: resultFilter, searchText: searchText)
        // Um produto que deixou de ser "possivelmente ausente" (revisão manual) sai da seleção.
        selectedProductIDs.formIntersection(filtered.selectableIDs)
    }

    private var selectionTitle: String {
        switch selectedProductIDs.count {
        case 0: "selecionar produtos"
        case 1: "1 selecionado"
        default: "\(selectedProductIDs.count) selecionados"
        }
    }

    private var subtitle: String {
        guard !isSelecting else {
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return search.isEmpty ? "" : "buscando \"\(search)\""
        }
        return "\(accountA.user.name) \(result.storeA.listingCount.formatted()) ↔ "
            + "\(accountB.user.name) \(result.storeB.listingCount.formatted()) produtos"
    }

    // MARK: - Lista

    @ViewBuilder
    private var resultList: some View {
        if filtered.isEmpty, !showsProblems {
            ContentUnavailableView.search(text: searchText)
                .frame(maxHeight: .infinity)
        } else {
            // `LazyVStack` em vez de `List`: mesmo raciocínio de
            // `AccountPublishedTabView.productList` — no idiom otimizado do Mac Catalyst, `List`
            // vira `NSTableView`, caro pra reconstruir do zero, e `.id(result.id)` (ver quem chama
            // esta view) reconstrói esta lista inteira a cada comparação nova.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if showsProblems {
                        ComparisonProblemsCard(result: result, onRetry: onRetry)
                    }
                    pairSection("mesmo produto", filtered.matches)
                    pairSection("precisa revisar", filtered.reviews)
                    if !filtered.missingInB.isEmpty {
                        // Só existe em A — postar cria ele em B.
                        missingSection(filtered.missingInB, source: accountA, destination: accountB)
                    }
                    if !filtered.missingInA.isEmpty {
                        // Só existe em B — postar cria ele em A.
                        missingSection(filtered.missingInA, source: accountB, destination: accountA)
                    }
                    unverifiedSection
                    pairSection("marcados como diferentes", filtered.rejected)
                }
                .frame(maxWidth: isCompact ? .infinity : 760)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
        }
    }

    private var showsProblems: Bool {
        searchText.isEmpty && (result.hasProblems || result.staleDecisionCount > 0)
    }

    @ViewBuilder
    private func pairSection(_ title: String, _ matches: [ProductMatch]) -> some View {
        if !matches.isEmpty {
            sectionHeader(title, count: matches.count, selectableIDs: nil)
            card {
                ForEach(matches) { match in
                    ProductMatchRowView(
                        match: match,
                        accountAName: accountA.user.name,
                        accountBName: accountB.user.name,
                        onDecide: { verdict in onDecide(verdict, match) },
                        onUndo: { onUndo(match) }
                    )
                    if match.id != matches.last?.id {
                        Divider().padding(.leading, 16 + 108 + 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unverifiedSection: some View {
        let listings = filtered.unverifiedA.map { ($0, accountA.user.name) } + filtered.unverifiedB.map { ($0, accountB.user.name) }
        if !listings.isEmpty {
            sectionHeader("não deu pra verificar", count: listings.count, selectableIDs: nil)
            card {
                ForEach(listings, id: \.0.id) { listing, storeName in
                    UnverifiedProductRowView(listing: listing, storeName: storeName)
                    if listing.id != listings.last?.0.id {
                        Divider().padding(.leading, 16 + 64 + 12)
                    }
                }
            }
        }
    }

    private func missingSection(
        _ products: [EnjoeiProduct],
        source: AccountSession,
        destination: AccountSession
    ) -> some View {
        Group {
            sectionHeader(
                "possivelmente ausentes em \(destination.user.name)",
                count: products.count,
                selectableIDs: products.map(\.id)
            )
            card {
                ForEach(products) { product in
                    UnmatchedProductRowView(
                        product: product,
                        sourceAccount: source,
                        destinationAccount: destination,
                        poster: poster,
                        postQueue: postQueue,
                        isSelecting: isSelecting,
                        isSelected: selectedProductIDs.contains(product.id),
                        onToggleSelection: { toggleSelection(productID: product.id) }
                    )
                    if product.id != products.last?.id {
                        Divider().padding(.leading, 16 + 64 + 12 + (isSelecting ? 36 : 0))
                    }
                }
            }
        }
    }

    /// "mesmo produto · 90" — nas seções selecionáveis, com "todos"/"nenhum" daquela seção à
    /// direita durante a seleção.
    private func sectionHeader(_ title: String, count: Int, selectableIDs: [Int]?) -> some View {
        HStack(spacing: 8) {
            Text("\(title) · \(count.formatted())")
                .foregroundStyle(.supportingText)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if isSelecting, let selectableIDs {
                let isFullySelected = selectableIDs.allSatisfy(selectedProductIDs.contains)
                Button(isFullySelected ? "nenhum" : "todos") {
                    selectedProductIDs = PublishedProductSections.togglingAll(selectableIDs, in: selectedProductIDs)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .fixedSize()
                .accessibilityLabel(isFullySelected ? "desmarcar todos em \(title)" : "selecionar todos em \(title)")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 16)
    }

    // MARK: - Barras

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(isAllSelected ? "nenhum" : "todos") {
                    selectedProductIDs = PublishedProductSections.togglingAll(filtered.selectableIDs, in: selectedProductIDs)
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
            if isCompact {
                if #available(iOS 26.0, macCatalyst 26.0, *) {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                } else {
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    selectButton
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    selectButton
                }
            }
        }
    }

    /// Sempre habilitado — sem nada selecionável (só pares/revisões, ou tudo filtrado) o toque não faz
    /// nada; um item da barra que se desabilita sozinho derruba o app no Mac (ver
    /// `ToolbarItemDisabled`).
    private var selectButton: some View {
        Button("selecionar") {
            guard !filtered.selectableIDs.isEmpty else { return }
            isSelecting = true
        }
        .fixedSize()
    }

    private var filterMenu: some View {
        Menu {
            Picker("filtro", selection: $resultFilter) {
                ForEach(ComparisonResultFilter.allCases, id: \.self) { filter in
                    Text(filter.label(result: result, accountAName: accountA.user.name, accountBName: accountB.user.name))
                        .tag(filter)
                }
            }
            .pickerStyle(.inline)
        } label: {
            // Ícone fixo, mesmo com um filtro ligado — no Mac, trocar a imagem de um item da barra
            // de cima passa pelo caminho do AppKit que derrubava o app (ver `ToolbarItemDisabled`).
            Label("filtrar resultados", systemImage: "line.3.horizontal.decrease")
        }
    }

    /// Uma ação só: mandar o que está marcado pra fila de ações, cada um pra conta onde ele
    /// possivelmente não existe.
    private var selectionBar: some View {
        Button {
            enqueueSelected()
        } label: {
            Label(
                selectedProductIDs.isEmpty ? "adicionar à fila" : "adicionar \(selectedProductIDs.count) à fila",
                systemImage: "paperplane.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tinted(.accentColor, size: 50))
        .disabled(selectedProductIDs.isEmpty)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Seleção

    private var isAllSelected: Bool {
        !filtered.selectableIDs.isEmpty && filtered.selectableIDs.allSatisfy(selectedProductIDs.contains)
    }

    private func toggleSelection(productID: Int) {
        if selectedProductIDs.contains(productID) {
            selectedProductIDs.remove(productID)
        } else {
            selectedProductIDs.insert(productID)
        }
    }

    private func endSelection() {
        selectedProductIDs.removeAll()
        isSelecting = false
    }

    /// Resolve cada id selecionado contra o resultado **completo** (não o filtrado pela busca),
    /// pra achar a origem/destino certos mesmo se o texto de busca mudar antes de confirmar.
    private func enqueueSelected() {
        for product in result.possiblyMissingInB where selectedProductIDs.contains(product.id) {
            postQueue.enqueue(product: product, source: accountA, destination: accountB)
        }
        for product in result.possiblyMissingInA where selectedProductIDs.contains(product.id) {
            postQueue.enqueue(product: product, source: accountB, destination: accountA)
        }
        endSelection()
    }
}
