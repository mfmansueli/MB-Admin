import SwiftUI

/// Resultado de uma comparação já carregada: busca, filtro, seleção múltipla e as três seções
/// (produtos em comum, só em A, só em B). Extraído de `AccountComparisonView` só por tamanho — quem
/// chama passa `.id(result.id)`, então cada comparação nova (trocar conta, ou comparar o mesmo par
/// de novo) sempre nasce com busca/filtro/seleção zerados, em vez de arrastar o que sobrou marcado
/// da comparação anterior.
struct ComparisonResultView: View {
    let result: AccountComparisonResult
    let accountA: AccountSession
    let accountB: AccountSession
    let poster: CrossAccountPoster
    let postQueue: PostQueue

    @State private var resultFilter: ResultFilter = .all
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedProductIDs: Set<Int> = []
    /// Cache de `filteredMatches`/`filteredOnlyInA`/`filteredOnlyInB` (ver `recomputeFilteredItems`)
    /// — sem isso, o filtro de busca rodava sobre os três resultados inteiros a cada leitura no
    /// `body` (seleção, contagem, etc.), várias vezes por render, numa comparação com muitos
    /// produtos. Mesmo raciocínio de `AccountPublishedTabView.filteredItems`.
    @State private var filteredMatches: [ProductMatch] = []
    @State private var filteredOnlyInA: [EnjoeiProduct] = []
    @State private var filteredOnlyInB: [EnjoeiProduct] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private enum ResultFilter: Hashable {
        case all
        case matches
        /// Só em conta A — ou seja, os que faltam na conta B.
        case onlyInA
        /// Só em conta B — os que faltam na conta A.
        case onlyInB
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                searchField
                resultFilterPicker
            }
            .padding(.horizontal, 20)

            if !filteredOnlyInA.isEmpty || !filteredOnlyInB.isEmpty {
                // Só os produtos das seções que o filtro atual realmente mostra — com "parecidos"
                // selecionado, por exemplo, não tem o que marcar, já que os pares não são
                // selecionáveis.
                let selectableIDs = selectableProductIDs(onlyInA: filteredOnlyInA, onlyInB: filteredOnlyInB)
                HStack {
                    Button(isSelecting ? "cancelar seleção" : "selecionar") {
                        isSelecting.toggle()
                        if !isSelecting { selectedProductIDs.removeAll() }
                    }
                    .buttonStyle(.bordered)

                    if isSelecting, !selectableIDs.isEmpty {
                        Button(
                            selectableIDs.isSubset(of: selectedProductIDs)
                                ? "desmarcar todos"
                                : "selecionar todos"
                        ) {
                            toggleSelectAll(selectableIDs)
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if isSelecting, !selectedProductIDs.isEmpty {
                        Button {
                            enqueueSelected()
                        } label: {
                            // `.onTint`: ver o mesmo caso no botão "comparar" de
                            // `AccountComparisonView`.
                            Text("adicionar \(selectedProductIDs.count) à fila").foregroundStyle(.onTint)
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 20)
            }

            if filteredMatches.isEmpty, filteredOnlyInA.isEmpty, filteredOnlyInB.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                // `LazyVStack` em vez de `List`: mesmo raciocínio de
                // `AccountPublishedTabView.productList` — no idiom otimizado do Mac Catalyst, `List`
                // vira `NSTableView`, caro pra reconstruir do zero, e `.id(result.id)` (ver quem
                // chama esta view) reconstrói esta lista inteira a cada comparação nova.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if resultFilter == .all || resultFilter == .matches, !filteredMatches.isEmpty {
                            Section {
                                ForEach(filteredMatches) { match in
                                    ProductMatchRowView(match: match)
                                    if match.id != filteredMatches.last?.id {
                                        Divider()
                                    }
                                }
                            } header: {
                                sectionHeader("produtos em comum")
                            }
                        }
                        if resultFilter == .all || resultFilter == .onlyInA, !filteredOnlyInA.isEmpty {
                            Section {
                                ForEach(filteredOnlyInA) { product in
                                    // Só existe em A — postar cria ele em B.
                                    UnmatchedProductRowView(
                                        product: product,
                                        sourceAccount: accountA,
                                        destinationAccount: accountB,
                                        poster: poster,
                                        postQueue: postQueue,
                                        isSelecting: isSelecting,
                                        isSelected: selectedProductIDs.contains(product.id),
                                        onToggleSelection: { toggleSelection(productID: product.id) }
                                    )
                                    if product.id != filteredOnlyInA.last?.id {
                                        Divider()
                                    }
                                }
                            } header: {
                                sectionHeader("só em \(accountA.user.name)")
                            }
                        }
                        if resultFilter == .all || resultFilter == .onlyInB, !filteredOnlyInB.isEmpty {
                            Section {
                                ForEach(filteredOnlyInB) { product in
                                    // Só existe em B — postar cria ele em A.
                                    UnmatchedProductRowView(
                                        product: product,
                                        sourceAccount: accountB,
                                        destinationAccount: accountA,
                                        poster: poster,
                                        postQueue: postQueue,
                                        isSelecting: isSelecting,
                                        isSelected: selectedProductIDs.contains(product.id),
                                        onToggleSelection: { toggleSelection(productID: product.id) }
                                    )
                                    if product.id != filteredOnlyInB.last?.id {
                                        Divider()
                                    }
                                }
                            } header: {
                                sectionHeader("só em \(accountB.user.name)")
                            }
                        }
                    }
                }
            }
        }
        .task { recomputeFilteredItems() }
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

    /// Refaz o filtro dos três resultados de uma vez só — ver `filteredMatches`/`filteredOnlyInA`/
    /// `filteredOnlyInB` no topo do arquivo.
    private func recomputeFilteredItems() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            filteredMatches = result.matches
            filteredOnlyInA = result.onlyInA
            filteredOnlyInB = result.onlyInB
            return
        }
        filteredMatches = result.matches.filter {
            $0.productA.title.localizedCaseInsensitiveContains(text)
                || $0.productB.title.localizedCaseInsensitiveContains(text)
        }
        filteredOnlyInA = result.onlyInA.filter { $0.title.localizedCaseInsensitiveContains(text) }
        filteredOnlyInB = result.onlyInB.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }

    private var searchField: some View {
        SearchField(placeholder: "buscar por nome", text: $searchText, isFocused: $isSearchFocused)
            .frame(maxWidth: .infinity)
    }

    private var resultFilterPicker: some View {
        let total = result.matches.count + result.onlyInA.count + result.onlyInB.count
        return Menu {
            Picker("filtro", selection: $resultFilter) {
                Text("todos (\(total))").tag(ResultFilter.all)
                Text("parecidos (\(result.matches.count))").tag(ResultFilter.matches)
                Text("não encontrados em \(accountA.user.name) (\(result.onlyInB.count))")
                    .tag(ResultFilter.onlyInB)
                Text("não encontrados em \(accountB.user.name) (\(result.onlyInA.count))")
                    .tag(ResultFilter.onlyInA)
            }
            .pickerStyle(.inline)
        } label: {
            HStack {
                // Tamanho mínimo fixo — mesmo raciocínio de `AccountPublishedTabView.filterPicker`/
                // `SmartPriceProductsListView.statusFilterPicker`: sem isso, trocar entre rótulos de
                // tamanhos bem diferentes ("todos (150)" vs. "não encontrados em fulano de tal
                // (23)") fazia o menu pular de tamanho de um jeito feio no meio da animação de
                // seleção, mais visível no iPad (mais espaço horizontal pro texto esticar).
                Text(resultFilterLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 130, minHeight: 32, alignment: .trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var resultFilterLabel: String {
        switch resultFilter {
        case .all:
            "todos (\(result.matches.count + result.onlyInA.count + result.onlyInB.count))"
        case .matches:
            "parecidos (\(result.matches.count))"
        case .onlyInB:
            "não encontrados em \(accountA.user.name) (\(result.onlyInB.count))"
        case .onlyInA:
            "não encontrados em \(accountB.user.name) (\(result.onlyInA.count))"
        }
    }

    /// Fundo opaco explícito — sem isso, o header de uma `Section` fica transparente e as rows
    /// parecem "passar por trás" dele enquanto a lista rola.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.background)
    }

    private func toggleSelection(productID: Int) {
        if selectedProductIDs.contains(productID) {
            selectedProductIDs.remove(productID)
        } else {
            selectedProductIDs.insert(productID)
        }
    }

    /// Ids selecionáveis de acordo com o que `resultFilter` está exibindo agora — os pares
    /// ("produtos em comum") nunca entram, porque `ProductMatchRowView` não tem seleção.
    private func selectableProductIDs(onlyInA: [EnjoeiProduct], onlyInB: [EnjoeiProduct]) -> Set<Int> {
        var ids: Set<Int> = []
        if resultFilter == .all || resultFilter == .onlyInA { ids.formUnion(onlyInA.map(\.id)) }
        if resultFilter == .all || resultFilter == .onlyInB { ids.formUnion(onlyInB.map(\.id)) }
        return ids
    }

    private func toggleSelectAll(_ ids: Set<Int>) {
        if ids.isSubset(of: selectedProductIDs) {
            selectedProductIDs.subtract(ids)
        } else {
            selectedProductIDs.formUnion(ids)
        }
    }

    /// Resolve cada id selecionado contra o resultado **completo** (não o filtrado pela busca),
    /// pra achar a origem/destino certos mesmo se o texto de busca mudar antes de confirmar.
    private func enqueueSelected() {
        for product in result.onlyInA where selectedProductIDs.contains(product.id) {
            postQueue.enqueue(product: product, source: accountA, destination: accountB)
        }
        for product in result.onlyInB where selectedProductIDs.contains(product.id) {
            postQueue.enqueue(product: product, source: accountB, destination: accountA)
        }
        selectedProductIDs.removeAll()
        isSelecting = false
    }
}
