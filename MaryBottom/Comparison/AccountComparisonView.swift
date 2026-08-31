import SwiftUI

/// Conteúdo do sheet aberto pelo botão "comparar produtos" em "suas contas": escolhe duas contas
/// logadas e mostra quais produtos parecem ser o mesmo item nas duas, e quais só existem numa.
struct AccountComparisonView: View {
    let accounts: [AccountSession]

    @State private var accountAID: EnjoeiAccountID?
    @State private var accountBID: EnjoeiAccountID?
    @State private var loader = AccountComparisonLoader()
    @State private var resultFilter: ResultFilter = .all
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedProductIDs: Set<Int> = []
    @State private var isShowingQueue = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountsStore.self) private var accountsStore

    private var poster: CrossAccountPoster { accountsStore.poster }

    private enum ResultFilter: Hashable {
        case all
        case matches
        /// Só em conta A — ou seja, os que faltam na conta B.
        case onlyInA
        /// Só em conta B — os que faltam na conta A.
        case onlyInB
    }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.count < 2 {
                    ContentUnavailableView(
                        "é preciso pelo menos duas contas logadas",
                        systemImage: "person.2",
                        description: Text("adicione outra conta pra poder comparar os produtos.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("comparar produtos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("fechar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingQueue = true
                    } label: {
                        if accountsStore.postQueue.isRunning {
                            ProgressView()
                        } else {
                            Label("fila de publicação", systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
        }
        .onAppear(perform: preselectAccounts)
        .sheet(isPresented: $isShowingQueue) {
            PostQueueView(postQueue: accountsStore.postQueue, poster: poster)
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    accountPicker("conta A", selection: $accountAID, excluding: accountBID)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        cooldownStatus
                    }
                    .padding(.top, 34)
                    accountPicker("conta B", selection: $accountBID, excluding: accountAID)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    guard let accountA, let accountB else { return }
                    loader.compare(accountA: accountA, accountB: accountB)
                } label: {
                    Text("comparar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(accountA == nil || accountB == nil || loader.phase == .loadingProducts)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            resultView
        }
    }

    /// Contagem regressiva do bloqueio de "postar em" — só aparece enquanto o bloqueio está ativo.
    @ViewBuilder
    private var cooldownStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let cooldownUntil = poster.cooldownUntil, poster.isInCooldown {
                let remaining = Int(cooldownUntil.timeIntervalSinceNow.rounded(.up))
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var resultView: some View {
        switch loader.phase {
        case .idle:
            ContentUnavailableView(
                "compare os produtos das duas contas",
                systemImage: "rectangle.on.rectangle",
                description: Text("escolha as duas contas acima e toque em \"comparar\".")
            )
            .frame(maxHeight: .infinity)
        case .loadingProducts:
            Spacer()
            ProgressView("carregando produtos…")
            Spacer()
        case .finished(let result):
            if let accountA, let accountB {
                let matches = filteredMatches(result.matches)
                let onlyInA = filteredProducts(result.onlyInA)
                let onlyInB = filteredProducts(result.onlyInB)

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        searchField
                        resultFilterPicker(result)
                    }
                    .padding(.horizontal, 20)

                    if !onlyInA.isEmpty || !onlyInB.isEmpty {
                        HStack {
                            Button(isSelecting ? "cancelar seleção" : "selecionar") {
                                isSelecting.toggle()
                                if !isSelecting { selectedProductIDs.removeAll() }
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            if isSelecting, !selectedProductIDs.isEmpty {
                                Button("adicionar \(selectedProductIDs.count) à fila") {
                                    enqueueSelected(result: result, accountA: accountA, accountB: accountB)
                                }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    if matches.isEmpty, onlyInA.isEmpty, onlyInB.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxHeight: .infinity)
                    } else {
                        List {
                            if resultFilter == .all || resultFilter == .matches, !matches.isEmpty {
                                Section {
                                    ForEach(matches) { match in
                                        ProductMatchRowView(match: match)
                                    }
                                } header: {
                                    sectionHeader("produtos em comum")
                                }
                            }
                            if resultFilter == .all || resultFilter == .onlyInA, !onlyInA.isEmpty {
                                Section {
                                    ForEach(onlyInA) { product in
                                        // Só existe em A — postar cria ele em B.
                                        UnmatchedProductRowView(
                                            product: product,
                                            sourceAccount: accountA,
                                            destinationAccount: accountB,
                                            poster: poster,
                                            postQueue: accountsStore.postQueue,
                                            isSelecting: isSelecting,
                                            isSelected: selectedProductIDs.contains(product.id),
                                            onToggleSelection: { toggleSelection(productID: product.id) }
                                        )
                                    }
                                } header: {
                                    sectionHeader("só em \(accountA.user.name)")
                                }
                            }
                            if resultFilter == .all || resultFilter == .onlyInB, !onlyInB.isEmpty {
                                Section {
                                    ForEach(onlyInB) { product in
                                        // Só existe em B — postar cria ele em A.
                                        UnmatchedProductRowView(
                                            product: product,
                                            sourceAccount: accountB,
                                            destinationAccount: accountA,
                                            poster: poster,
                                            postQueue: accountsStore.postQueue,
                                            isSelecting: isSelecting,
                                            isSelected: selectedProductIDs.contains(product.id),
                                            onToggleSelection: { toggleSelection(productID: product.id) }
                                        )
                                    }
                                } header: {
                                    sectionHeader("só em \(accountB.user.name)")
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
        }
    }

    private func filteredMatches(_ matches: [ProductMatch]) -> [ProductMatch] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return matches }
        return matches.filter {
            $0.productA.title.localizedCaseInsensitiveContains(text)
                || $0.productB.title.localizedCaseInsensitiveContains(text)
        }
    }

    private func filteredProducts(_ products: [EnjoeiProduct]) -> [EnjoeiProduct] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return products }
        return products.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("buscar por nome", text: $searchText)
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
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { isSearchFocused = true }
    }

    private func resultFilterPicker(_ result: AccountComparisonResult) -> some View {
        let total = result.matches.count + result.onlyInA.count + result.onlyInB.count
        return Menu {
            Picker("filtro", selection: $resultFilter) {
                Text("todos (\(total))").tag(ResultFilter.all)
                Text("parecidos (\(result.matches.count))").tag(ResultFilter.matches)
                Text("não encontrados em \(accountA?.user.name ?? "conta A") (\(result.onlyInB.count))")
                    .tag(ResultFilter.onlyInB)
                Text("não encontrados em \(accountB?.user.name ?? "conta B") (\(result.onlyInA.count))")
                    .tag(ResultFilter.onlyInA)
            }
            .pickerStyle(.inline)
        } label: {
            HStack {
                Text(resultFilterLabel(result))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func resultFilterLabel(_ result: AccountComparisonResult) -> String {
        switch resultFilter {
        case .all:
            "todos (\(result.matches.count + result.onlyInA.count + result.onlyInB.count))"
        case .matches:
            "parecidos (\(result.matches.count))"
        case .onlyInB:
            "não encontrados em \(accountA?.user.name ?? "conta A") (\(result.onlyInB.count))"
        case .onlyInA:
            "não encontrados em \(accountB?.user.name ?? "conta B") (\(result.onlyInA.count))"
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

    /// Resolve cada id selecionado contra o resultado **completo** (não o filtrado pela busca),
    /// pra achar a origem/destino certos mesmo se o texto de busca mudar antes de confirmar.
    private func enqueueSelected(result: AccountComparisonResult, accountA: AccountSession?, accountB: AccountSession?) {
        guard let accountA, let accountB else { return }
        for product in result.onlyInA where selectedProductIDs.contains(product.id) {
            accountsStore.postQueue.enqueue(product: product, source: accountA, destination: accountB)
        }
        for product in result.onlyInB where selectedProductIDs.contains(product.id) {
            accountsStore.postQueue.enqueue(product: product, source: accountB, destination: accountA)
        }
        selectedProductIDs.removeAll()
        isSelecting = false
    }

    @ViewBuilder
    private func accountPicker(
        _ title: String,
        selection: Binding<EnjoeiAccountID?>,
        excluding otherID: EnjoeiAccountID?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(accounts.filter { $0.id != otherID }) { account in
                    Button(account.user.name) { selection.wrappedValue = account.id }
                }
            } label: {
                // Mesma row usada em "suas contas" — só troca a conta selecionada, sem duplicar
                // o layout dela aqui.
                if let account = accounts.first(where: { $0.id == selection.wrappedValue }) {
                    AccountRowView(account: account)
                } else {
                    Text("selecione uma conta")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var accountA: AccountSession? {
        accounts.first { $0.id == accountAID }
    }

    private var accountB: AccountSession? {
        accounts.first { $0.id == accountBID }
    }

    /// Já pré-seleciona as duas primeiras contas, pra quem só tem duas logadas ir direto no botão.
    private func preselectAccounts() {
        guard accounts.count >= 2 else { return }
        if accountAID == nil { accountAID = accounts[0].id }
        if accountBID == nil { accountBID = accounts[1].id }
    }
}
