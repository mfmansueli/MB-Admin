import SwiftUI

/// Resultado de uma comparação já carregada, em seções-cartão: mesmo produto, precisa revisar,
/// produtos com variantes (versões que dividem a mesma foto e onde cada uma está), repetidos dentro
/// de cada loja, possivelmente ausentes em cada loja (com a nota de quando a outra loja tem outra
/// versão), não deu pra verificar e marcados como diferentes — com o
/// aviso de comparação incompleta no topo, o filtro na barra de cima, a busca (no iPhone, a lupa na
/// barra de baixo) e a seleção múltipla pra fila de ações: os possivelmente ausentes (postar na outra
/// loja) e os grupos de repetidos certos (fica o anúncio de "manter", os outros vão pra fila pra
/// serem apagados — `DuplicateCleanup`). Quem chama passa `.id(result.id)`: cada comparação nova
/// nasce com busca/filtro/seleção zerados, mas uma revisão manual (mesmo `id`, `revision` nova) só
/// atualiza as seções.
///
/// Desempenho com milhares de produtos: cada linha é filha direta da `LazyVStack` (o cartão é
/// desenhado linha a linha, `ComparisonCardRow`), então só as linhas perto da tela existem — com
/// foto, sheet e menu. As linhas são `Equatable` pelo dado que mostram: um render da lista (marcar um
/// item, trocar a seleção) não refaz as que não mudaram.
struct ComparisonResultView: View {
    let result: AccountComparisonResult
    let accountA: AccountSession
    let accountB: AccountSession
    let poster: CrossAccountPoster
    let postQueue: PostQueue
    var onDecide: (ComparisonDecision.Verdict, ProductMatch) -> Void
    var onUndo: (ProductMatch) -> Void
    var onDecideDuplicate: (ComparisonDecision.Verdict, StoreDuplicateGroup) -> Void
    var onUndoDuplicate: (StoreDuplicateGroup) -> Void
    var onRetry: () -> Void

    @State private var resultFilter: ComparisonResultFilter = .all
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selection = ComparisonSelection()
    @State private var isConfirmingDuplicateDeletion = false
    /// Cache do filtro + busca (ver `recomputeFilteredItems`) — sem isso, o filtro rodava sobre os
    /// três resultados inteiros a cada leitura no `body`, várias vezes por render, numa comparação
    /// com muitos produtos. Mesmo raciocínio de `AccountPublishedTabView.sections`. Já nasce montado
    /// (sem filtro nem busca), pra o primeiro quadro não ser a tela de "nada encontrado".
    @State private var filtered: ComparisonFilteredResult
    @State private var searchDebounceTask: Task<Void, Never>?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        result: AccountComparisonResult,
        accountA: AccountSession,
        accountB: AccountSession,
        poster: CrossAccountPoster,
        postQueue: PostQueue,
        onDecide: @escaping (ComparisonDecision.Verdict, ProductMatch) -> Void = { _, _ in },
        onUndo: @escaping (ProductMatch) -> Void = { _ in },
        onDecideDuplicate: @escaping (ComparisonDecision.Verdict, StoreDuplicateGroup) -> Void = { _, _ in },
        onUndoDuplicate: @escaping (StoreDuplicateGroup) -> Void = { _ in },
        onRetry: @escaping () -> Void = {}
    ) {
        self.result = result
        self.accountA = accountA
        self.accountB = accountB
        self.poster = poster
        self.postQueue = postQueue
        self.onDecide = onDecide
        self.onUndo = onUndo
        self.onDecideDuplicate = onDecideDuplicate
        self.onUndoDuplicate = onUndoDuplicate
        self.onRetry = onRetry
        _filtered = State(initialValue: ComparisonFilteredResult(result: result, filter: .all, searchText: ""))
    }

    private var isCompact: Bool { horizontalSizeClass != .regular }

    var body: some View {
        // Uma vez por render: os anúncios dos repetidos que já estão na fila, apagando ou apagados.
        let states = duplicateStates()
        let selectableGroups = selectableGroupIDs(states)
        resultList(states: states)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(isSelecting ? selectionTitle : "comparar produtos")
            .navigationSubtitleIfAvailable(subtitle)
            .toolbar { toolbarContent(selectableGroups: selectableGroups) }
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
                    ComparisonSelectionBar(
                        showsPost: !filtered.selectableIDs.isEmpty,
                        postCount: selection.productIDs.count,
                        showsDelete: !selectableGroups.isEmpty,
                        deleteCount: duplicateDeletions(states).count,
                        onPost: enqueueSelected,
                        onDelete: { isConfirmingDuplicateDeletion = true }
                    )
                }
            }
            .permanentDeleteConfirmation(
                isPresented: $isConfirmingDuplicateDeletion,
                productCount: duplicateDeletions(states).count,
                note: duplicateDeletionNote(count: duplicateDeletions(states).count)
            ) {
                deleteSelectedDuplicates()
            }
            .toolbar(isSelecting ? .hidden : .automatic, for: .bottomBar)
            // Uma revisão manual recalcula o resultado com o mesmo `id` — só refiltra.
            .onChange(of: result.revision) { _, _ in recomputeFilteredItems() }
            .onChange(of: resultFilter) { _, _ in
                // Trocar de filtro com itens marcados deixaria parte da seleção escondida, mas
                // ainda indo pra fila.
                selection.removeAll()
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
        // Um produto que deixou de ser "possivelmente ausente" (revisão manual), ou um grupo que
        // deixou de ser repetido certo, sai da seleção.
        selection.keepOnly(
            productIDs: Set(filtered.selectableIDs),
            groupIDs: Set((filtered.duplicatesA + filtered.duplicatesB).filter(\.isCertain).map(\.id))
        )
    }

    private var selectionTitle: String {
        switch selection.count {
        case 0: "selecionar produtos"
        case 1: "1 selecionado"
        default: "\(selection.count) selecionados"
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
    private func resultList(states: [Int: DuplicateListingState]) -> some View {
        if filtered.isEmpty, !showsProblems, !(searchText.isEmpty && result.learning.hasChanges) {
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
                    if searchText.isEmpty, result.learning.hasChanges {
                        ComparisonLearningCard(learning: result.learning)
                    }
                    pairSection("mesmo produto", filtered.matches)
                    pairSection("precisa revisar", filtered.reviews)
                    familySection
                    duplicateSection(filtered.duplicatesA, storeName: accountA.user.name, states: states)
                    duplicateSection(filtered.duplicatesB, storeName: accountB.user.name, states: states)
                    if !filtered.missingInB.isEmpty {
                        // Só existe em A — postar cria ele em B.
                        missingSection(filtered.missingInB, source: accountA, destination: accountB)
                    }
                    if !filtered.missingInA.isEmpty {
                        // Só existe em B — postar cria ele em A.
                        missingSection(filtered.missingInA, source: accountB, destination: accountA)
                    }
                    unverifiedSection
                    rejectedSection
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
            sectionHeader(title, count: matches.count)
            pairRows(matches, isFirstSegment: true, isLastSegment: true)
        }
    }

    /// As linhas de pares, como um pedaço do cartão: `isFirstSegment`/`isLastSegment` dizem se a
    /// primeira/última daqui também é a primeira/última do cartão (a seção de marcados como
    /// diferentes junta pares e grupos de repetidos no mesmo cartão).
    private func pairRows(_ matches: [ProductMatch], isFirstSegment: Bool, isLastSegment: Bool) -> some View {
        let firstID = matches.first?.id
        let lastID = matches.last?.id
        return ForEach(matches) { match in
            ProductMatchRowView(
                match: match,
                accountAName: accountA.user.name,
                accountBName: accountB.user.name,
                onDecide: { verdict in onDecide(verdict, match) },
                onUndo: { onUndo(match) }
            )
            .equatable()
            .comparisonCardRow(isFirst: isFirstSegment && match.id == firstID, isLast: isLastSegment && match.id == lastID)
            if match.id != lastID || !isLastSegment {
                rowDivider(inset: 108 + 12)
            }
        }
    }

    @ViewBuilder
    private var familySection: some View {
        let families = filtered.families
        if !families.isEmpty {
            sectionHeader("produtos com variantes", count: families.count)
            let firstID = families.first?.id
            let lastID = families.last?.id
            ForEach(families) { family in
                ProductFamilyCardView(family: family, accountAName: accountA.user.name, accountBName: accountB.user.name)
                    .equatable()
                    .comparisonCardRow(isFirst: family.id == firstID, isLast: family.id == lastID)
                if family.id != lastID {
                    rowDivider(inset: 52 + 12)
                }
            }
        }
    }

    @ViewBuilder
    private func duplicateSection(_ groups: [StoreDuplicateGroup], storeName: String, states: [Int: DuplicateListingState]) -> some View {
        if !groups.isEmpty {
            sectionHeader(
                "repetidos em \(storeName)",
                count: groups.count,
                selectableGroupIDs: groups.filter { DuplicateCleanup.isSelectable($0, states: states) }.map(\.id)
            )
            duplicateRows(groups, states: states, isFirstSegment: true, isLastSegment: true)
        }
    }

    private func duplicateRows(
        _ groups: [StoreDuplicateGroup],
        states: [Int: DuplicateListingState],
        isFirstSegment: Bool,
        isLastSegment: Bool
    ) -> some View {
        let firstID = groups.first?.id
        let lastID = groups.last?.id
        return ForEach(groups) { group in
            let groupStates = Dictionary(uniqueKeysWithValues: group.products.compactMap { product in states[product.id].map { (product.id, $0) } })
            let choice = selection.keptByGroup[group.id]
            StoreDuplicateRowView(
                group: group,
                states: groupStates,
                isSelecting: isSelecting,
                isSelected: selection.groupIDs.contains(group.id),
                keptID: DuplicateCleanup.isSelectable(group, states: groupStates)
                    ? DuplicateCleanup.kept(group, choice: choice, states: groupStates)
                    : nil,
                onDecide: { verdict in onDecideDuplicate(verdict, group) },
                onUndo: { onUndoDuplicate(group) },
                onChooseKept: {
                    selection.select(groupID: group.id)
                    isSelecting = true
                },
                onToggleSelection: { selection.toggle(groupID: group.id) },
                onKeep: { productID in selection.keep(productID, inGroup: group.id) }
            )
            .equatable()
            .comparisonCardRow(isFirst: isFirstSegment && group.id == firstID, isLast: isLastSegment && group.id == lastID)
            if group.id != lastID || !isLastSegment {
                rowDivider(inset: 52 + 12)
            }
        }
    }

    @ViewBuilder
    private var unverifiedSection: some View {
        let listingsA = filtered.unverifiedA
        let listingsB = filtered.unverifiedB
        if !listingsA.isEmpty || !listingsB.isEmpty {
            sectionHeader("não deu pra verificar", count: listingsA.count + listingsB.count)
            unverifiedRows(listingsA, storeName: accountA.user.name, isFirstSegment: true, isLastSegment: listingsB.isEmpty)
            unverifiedRows(listingsB, storeName: accountB.user.name, isFirstSegment: listingsA.isEmpty, isLastSegment: true)
        }
    }

    private func unverifiedRows(
        _ listings: [UnverifiedListing],
        storeName: String,
        isFirstSegment: Bool,
        isLastSegment: Bool
    ) -> some View {
        let firstID = listings.first?.id
        let lastID = listings.last?.id
        return ForEach(listings) { listing in
            UnverifiedProductRowView(listing: listing, storeName: storeName)
                .equatable()
                .comparisonCardRow(isFirst: isFirstSegment && listing.id == firstID, isLast: isLastSegment && listing.id == lastID)
            if listing.id != lastID || !isLastSegment {
                rowDivider(inset: 64 + 12)
            }
        }
    }

    /// Pares marcados como produtos diferentes e grupos marcados como não repetidos — o que você
    /// revisou como "não é", com o desfazer de cada um.
    @ViewBuilder
    private var rejectedSection: some View {
        let pairs = filtered.rejected
        let groups = filtered.dismissedDuplicates
        if !pairs.isEmpty || !groups.isEmpty {
            sectionHeader("marcados como diferentes", count: pairs.count + groups.count)
            pairRows(pairs, isFirstSegment: true, isLastSegment: groups.isEmpty)
            duplicateRows(groups, states: [:], isFirstSegment: pairs.isEmpty, isLastSegment: true)
        }
    }

    private func missingSection(
        _ products: [EnjoeiProduct],
        source: AccountSession,
        destination: AccountSession
    ) -> some View {
        let firstID = products.first?.id
        let lastID = products.last?.id
        return Group {
            sectionHeader(
                "possivelmente ausentes em \(destination.user.name)",
                count: products.count,
                selectableIDs: products.map(\.id)
            )
            ForEach(products) { product in
                UnmatchedProductRowView(
                    product: product,
                    sourceAccount: source,
                    destinationAccount: destination,
                    poster: poster,
                    postQueue: postQueue,
                    otherVersionsNote: OtherVersion.summary(
                        result.otherVersions[ListingKey(sellerID: source.user.id, productID: product.id)] ?? [],
                        storeName: destination.user.name
                    ),
                    isSelecting: isSelecting,
                    isSelected: selection.productIDs.contains(product.id),
                    onToggleSelection: { selection.toggle(productID: product.id) }
                )
                .equatable()
                .comparisonCardRow(isFirst: product.id == firstID, isLast: product.id == lastID)
                if product.id != lastID {
                    rowDivider(inset: 64 + 12 + (isSelecting ? 36 : 0))
                }
            }
        }
    }

    /// Começa onde começa o texto da linha (margem + foto + espaçamento), dentro do cartão.
    private func rowDivider(inset: CGFloat) -> some View {
        Divider()
            .padding(.leading, 16 + inset)
            .padding(.horizontal, 16)
    }

    /// "mesmo produto · 90" — nas seções selecionáveis, com "todos"/"nenhum" daquela seção à
    /// direita durante a seleção.
    private func sectionHeader(_ title: String, count: Int, selectableIDs: [Int] = [], selectableGroupIDs: [String] = []) -> some View {
        HStack(spacing: 8) {
            Text("\(title) · \(count.formatted())")
                .foregroundStyle(.supportingText)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if isSelecting, !selectableIDs.isEmpty || !selectableGroupIDs.isEmpty {
                let isFullySelected = selection.isFullySelected(productIDs: selectableIDs, groupIDs: selectableGroupIDs)
                Button(isFullySelected ? "nenhum" : "todos") {
                    selection.toggleAll(productIDs: selectableIDs, groupIDs: selectableGroupIDs)
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

    // MARK: - Barras

    @ToolbarContentBuilder
    private func toolbarContent(selectableGroups: [String]) -> some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let isAllSelected = selection.isFullySelected(productIDs: filtered.selectableIDs, groupIDs: selectableGroups)
                Button(isAllSelected ? "nenhum" : "todos") {
                    selection.toggleAll(productIDs: filtered.selectableIDs, groupIDs: selectableGroups)
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
                    selectButton(hasSelectableGroups: !selectableGroups.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    selectButton(hasSelectableGroups: !selectableGroups.isEmpty)
                }
            }
        }
    }

    /// Sempre habilitado — sem nada selecionável (só pares/revisões, ou tudo filtrado) o toque não faz
    /// nada; um item da barra que se desabilita sozinho derruba o app no Mac (ver
    /// `ToolbarItemDisabled`).
    private func selectButton(hasSelectableGroups: Bool) -> some View {
        Button("selecionar") {
            guard !filtered.selectableIDs.isEmpty || hasSelectableGroups else { return }
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

    // MARK: - Seleção

    private func endSelection() {
        selection.removeAll()
        isSelecting = false
    }

    /// Resolve cada id selecionado contra o resultado **completo** (não o filtrado pela busca),
    /// pra achar a origem/destino certos mesmo se o texto de busca mudar antes de confirmar.
    private func enqueueSelected() {
        for product in result.possiblyMissingInB where selection.productIDs.contains(product.id) {
            postQueue.enqueue(product: product, source: accountA, destination: accountB)
        }
        for product in result.possiblyMissingInA where selection.productIDs.contains(product.id) {
            postQueue.enqueue(product: product, source: accountB, destination: accountA)
        }
        selection.removeProducts()
        if selection.isEmpty { endSelection() }
    }

    // MARK: - Repetidos

    /// Os anúncios de todos os grupos de repetidos (não só os filtrados): na fila, apagando, apagados.
    private func duplicateStates() -> [Int: DuplicateListingState] {
        var reader = DuplicateListingStateReader(queue: postQueue)
        return reader.states(of: result.duplicatesA, account: accountA)
            .merging(reader.states(of: result.duplicatesB, account: accountB)) { $1 }
    }

    /// Os grupos na tela em que dá pra escolher um e apagar os outros.
    private func selectableGroupIDs(_ states: [Int: DuplicateListingState]) -> [String] {
        (filtered.duplicatesA + filtered.duplicatesB).filter { DuplicateCleanup.isSelectable($0, states: states) }.map(\.id)
    }

    /// Cada anúncio a mais dos grupos marcados, com a conta dele — contra o resultado completo.
    private func duplicateDeletions(_ states: [Int: DuplicateListingState]) -> [(product: EnjoeiProduct, account: AccountSession)] {
        guard !selection.groupIDs.isEmpty else { return [] }
        return [(result.duplicatesA, accountA), (result.duplicatesB, accountB)].flatMap { groups, account in
            groups
                .filter { selection.groupIDs.contains($0.id) }
                .flatMap { DuplicateCleanup.deletions($0, choice: selection.keptByGroup[$0.id], states: states) }
                .map { (product: $0, account: account) }
        }
    }

    private func duplicateDeletionNote(count: Int) -> String {
        let kept = "fica um anúncio de cada produto: o marcado como \"manter\"."
        guard count > 1 else { return kept }
        return "\(kept) \(PostQueueStatusText.queuePaceNote(interval: postQueue.interval(for: .delete)))"
    }

    /// Lê o estado de novo na hora de confirmar — algo pode ter entrado na fila enquanto o alerta
    /// estava aberto.
    private func deleteSelectedDuplicates() {
        for deletion in duplicateDeletions(duplicateStates()) {
            postQueue.enqueueDelete(product: deletion.product, account: deletion.account)
        }
        selection.removeGroups()
        if selection.isEmpty { endSelection() }
    }
}
