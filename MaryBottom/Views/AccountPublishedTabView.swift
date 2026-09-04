import SwiftUI

/// Aba "publicados" de `AccountDetailView`: ação de megafonar, busca, filtro, seleção múltipla e
/// lista de produtos publicados. Extraído pra arquivo próprio só por tamanho — o estado que
/// também importa pro resto de `AccountDetailView` (toolbar, troca de aba) continua lá, passado
/// aqui por `@Binding`, pra sobreviver a trocar pra aba "inativos" e voltar sem perder filtro,
/// busca ou seleção em andamento.
struct AccountPublishedTabView: View {
    let account: AccountSession

    @Binding var filter: AccountProductFilter
    @Binding var searchText: String
    @Binding var isSelecting: Bool
    @Binding var selectedIDs: Set<Int>
    @Binding var bulkAction: AccountBulkAction
    @Binding var discountBulkAction: AccountDiscountBulkAction
    /// Compartilhado com `AccountDetailView` — o botão "acompanhar" mora no toolbar dela, fora
    /// daqui.
    @Binding var isFollowing: Bool

    @Environment(AccountsStore.self) private var accountsStore
    /// Quantas vezes repetir a lista. Fica guardado entre execuções do app (0 = infinito). Por
    /// conta: com contas rodando em paralelo, uma preferência global faria trocar a velocidade de
    /// uma afetar silenciosamente as outras já em andamento.
    @AppStorage private var storedRounds: Int
    /// Intervalo entre um megafone e o próximo, em milissegundos.
    @AppStorage private var storedSpeed: Int
    @FocusState private var isSearchFocused: Bool

    @State private var isConfirmingBulkApply = false
    @State private var isConfirmingBulkRepost = false
    @State private var isConfirmingBulkDelete = false
    @State private var isConfirmingBulkInactivate = false
    /// Cache de `filteredItems` (ver `recomputeFilteredItems`) — sem isso, cada leitura (lista,
    /// "selecionar todos", contagem) refiltrava/reordenava a lista inteira de publicados do zero,
    /// várias vezes por digitação.
    @State private var filteredItems: [MegaphoneItem] = []
    @State private var searchDebounceTask: Task<Void, Never>?

    private var runner: MegaphoneRunner { account.runner }

    init(
        account: AccountSession,
        filter: Binding<AccountProductFilter>,
        searchText: Binding<String>,
        isSelecting: Binding<Bool>,
        selectedIDs: Binding<Set<Int>>,
        bulkAction: Binding<AccountBulkAction>,
        discountBulkAction: Binding<AccountDiscountBulkAction>,
        isFollowing: Binding<Bool>
    ) {
        self.account = account
        _filter = filter
        _searchText = searchText
        _isSelecting = isSelecting
        _selectedIDs = selectedIDs
        _bulkAction = bulkAction
        _discountBulkAction = discountBulkAction
        _isFollowing = isFollowing
        _storedRounds = AppStorage(wrappedValue: 1, "megaphone.rounds.\(account.id)")
        _storedSpeed = AppStorage(wrappedValue: MegaphoneSpeed.standard.milliseconds, "megaphone.speed.\(account.id)")
    }

    private var rounds: MegaphoneRounds { MegaphoneRounds(rawValue: storedRounds) }
    private var speed: MegaphoneSpeed { MegaphoneSpeed(milliseconds: storedSpeed) }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                actionButtons
                roundsMenu
                speedMenu
            }

            MegaphoneProgressView(runner: runner)

            HStack(spacing: 12) {
                searchField
                filterPicker
            }

            selectionBar

            productList
        }
        // Vale mudar o intervalo no meio da rodada: o laço lê o valor a cada produto.
        .onChange(of: storedSpeed) { _, milliseconds in
            runner.delayBetweenProducts = MegaphoneSpeed(milliseconds: milliseconds).duration
        }
        // A seleção só faz sentido dentro do filtro "pede desconto" — trocar de filtro (ou sair
        // dele) com itens marcados deixaria a seleção "invisível" mas ainda contando pro botão de
        // aplicar em massa.
        .onChange(of: filter) { _, _ in
            isSelecting = false
            selectedIDs.removeAll()
            bulkAction = .repost
            discountBulkAction = .applyDiscount
            recomputeFilteredItems()
        }
        .task { recomputeFilteredItems() }
        .onChange(of: runner.items) { _, _ in recomputeFilteredItems() }
        // Debounce: espera a digitação parar por 200ms antes de refiltrar, em vez de refazer o
        // filtro (potencialmente sobre centenas de produtos publicados) a cada tecla.
        .onChange(of: searchText) { _, _ in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                recomputeFilteredItems()
            }
        }
    }

    /// Seleção múltipla da lista de publicados — o seletor de ação em massa muda conforme o
    /// filtro atual (`bulkActionButton`), mas as quatro ações possíveis (aplicar desconto,
    /// repostar, inativar, apagar) e suas confirmações são as mesmas nos dois.
    @ViewBuilder
    private var selectionBar: some View {
        if !filteredItems.isEmpty {
            SelectionToggleBar(
                isSelecting: $isSelecting,
                hasItems: true,
                isAllSelected: isAllFilteredSelected,
                hasSelection: !selectedIDs.isEmpty,
                onToggleSelecting: {
                    isSelecting.toggle()
                    if !isSelecting {
                        selectedIDs.removeAll()
                        bulkAction = .repost
                        discountBulkAction = .applyDiscount
                    }
                },
                onToggleSelectAll: { toggleSelectAllFiltered() }
            ) {
                bulkActionButton
            }
            .confirmationDialog(
                "aplicar desconto e megafonar \(selectedIDs.count) produtos?",
                isPresented: $isConfirmingBulkApply,
                titleVisibility: .visible
            ) {
                Button("aplicar desconto") { applyDiscountToSelected() }
                Button("cancelar", role: .cancel) {}
            } message: {
                Text("cada produto vai pro preço com desconto sugerido pelo megafone, e é megafonado na hora.")
            }
            .confirmationDialog(
                "repostar \(selectedIDs.count) produtos?",
                isPresented: $isConfirmingBulkRepost,
                titleVisibility: .visible
            ) {
                Button("repostar") { repostSelected() }
                Button("cancelar", role: .cancel) {}
            } message: {
                Text("entra na fila de ações, reaproveitando título, descrição, preço e fotos de cada um — acompanhe o andamento por lá.")
            }
            .confirmationDialog(
                "apagar \(selectedIDs.count) produtos?",
                isPresented: $isConfirmingBulkDelete,
                titleVisibility: .visible
            ) {
                Button("apagar", role: .destructive) { deleteSelected() }
                Button("cancelar", role: .cancel) {}
            } message: {
                Text("ação irreversível: cada anúncio selecionado entra na fila de ações e é apagado do enjoei de vez, sem chance de recuperar.")
            }
            .confirmationDialog(
                "inativar \(selectedIDs.count) produtos?",
                isPresented: $isConfirmingBulkInactivate,
                titleVisibility: .visible
            ) {
                Button("inativar") { inactivateSelected() }
                Button("cancelar", role: .cancel) {}
            } message: {
                Text("cada anúncio selecionado entra na fila de ações e sai da vitrine de publicados — dá pra reativar depois direto no enjoei.")
            }
        }
    }

    // Cada ação tem sua própria confirmação antes de entrar na fila (`isConfirmingBulkApply`/
    // `isConfirmingBulkRepost`/`isConfirmingBulkInactivate`/`isConfirmingBulkDelete`, todas na
    // `selectionBar`) — os dois filtros reaproveitam as mesmas quatro, só o conjunto de opções do
    // seletor muda.
    @ViewBuilder
    private var bulkActionButton: some View {
        switch filter {
        case .discountOnly:
            BulkActionSelector(selection: $discountBulkAction, selectedCount: selectedIDs.count) {
                switch discountBulkAction {
                case .applyDiscount: isConfirmingBulkApply = true
                case .repost: isConfirmingBulkRepost = true
                case .inactivate: isConfirmingBulkInactivate = true
                case .delete: isConfirmingBulkDelete = true
                }
            }
        case .all:
            BulkActionSelector(selection: $bulkAction, selectedCount: selectedIDs.count) {
                switch bulkAction {
                case .repost: isConfirmingBulkRepost = true
                case .inactivate: isConfirmingBulkInactivate = true
                case .delete: isConfirmingBulkDelete = true
                }
            }
        }
    }

    private var isAllFilteredSelected: Bool {
        !filteredItems.isEmpty && filteredItems.allSatisfy { selectedIDs.contains($0.id) }
    }

    private func toggleSelectAllFiltered() {
        let ids = filteredItems.map(\.id)
        if isAllFilteredSelected {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    private func applyDiscountToSelected() {
        for id in selectedIDs {
            runner.applyDiscount(for: id)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    /// Mesma fila de ações usada pelo "repostar produto" de cada linha — origem e destino são
    /// a própria conta.
    private func repostSelected() {
        for item in filteredItems where selectedIDs.contains(item.id) {
            accountsStore.postQueue.enqueue(product: item.product, source: account, destination: account)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    /// Mesma fila de ações usada pelo "apagar produto" de cada linha.
    private func deleteSelected() {
        for item in filteredItems where selectedIDs.contains(item.id) {
            accountsStore.postQueue.enqueueDelete(product: item.product, account: account)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    /// Mesma fila de ações usada pelo "inativar produto" de cada linha.
    private func inactivateSelected() {
        for item in filteredItems where selectedIDs.contains(item.id) {
            accountsStore.postQueue.enqueueInactivate(product: item.product, account: account)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }

    private func toggleSelection(itemID: Int) {
        if selectedIDs.contains(itemID) {
            selectedIDs.remove(itemID)
        } else {
            selectedIDs.insert(itemID)
        }
    }

    private func startLoading() {
        runner.delayBetweenProducts = speed.duration
        runner.start(sellerID: account.user.id, rounds: rounds)
    }

    private var roundsMenu: some View {
        Menu {
            Picker("repetições", selection: $storedRounds) {
                ForEach(MegaphoneRounds.presets) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            // Sem isso, o Menu trata o Picker como um submenu à parte ("repetições" com seta),
            // exigindo um segundo toque pra ver as opções — .inline mostra tudo de uma vez.
            .pickerStyle(.inline)
        } label: {
            HStack {
                Text(rounds.label)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .disabled(runner.isRunning)
    }

    private var speedMenu: some View {
        Menu {
            Picker("intervalo", selection: $storedSpeed) {
                ForEach(MegaphoneSpeed.presets) { option in
                    Text(option.label).tag(option.milliseconds)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack {
                Text(speed.label)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
    }

    /// Só faz sentido pausar/parar quando já está megafonando de verdade — durante a busca (seja
    /// pelo carregamento automático ou pelo botão), não tem o que pausar ainda.
    private var isMegaphoning: Bool {
        switch runner.phase {
        case .megaphoning, .paused: true
        case .idle, .loadingProducts, .checkingExposure, .finished, .cancelled, .failed: false
        }
    }

    /// Botão(ões) de ação: sozinho no lugar do "megafonar" quando parado, ou pausar+parar juntos no
    /// mesmo lugar quando rodando — os três (isso e os dois menus de configuração) vivem na mesma
    /// `HStack`, então cada botão fica com largura flexível pra dividir o espaço.
    @ViewBuilder
    private var actionButtons: some View {
        if isMegaphoning {
            Button {
                if runner.isPaused { runner.resume() } else { runner.pause() }
            } label: {
                Label(
                    runner.isPaused ? "continuar" : "pausar",
                    systemImage: runner.isPaused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                runner.cancel()
            } label: {
                Label("parar", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else if runner.isRunning {
            EmptyView()
        } else {
            Button {
                startLoading()
            } label: {
                // A quantidade de vezes já aparece ao lado, no menu de repetições — sem repetir
                // aqui.
                Label("megafonar", systemImage: "megaphone.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var searchField: some View {
        if !runner.items.isEmpty {
            SearchField(placeholder: "buscar por nome", text: $searchText, isFocused: $isSearchFocused)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var filterPicker: some View {
        if !runner.items.isEmpty {
            Menu {
                Picker("filtro", selection: $filter) {
                    Text("todos os anúncios").tag(AccountProductFilter.all)
                    Text("anúncios que pedem desconto").tag(AccountProductFilter.discountOnly)
                }
                .pickerStyle(.inline)
            } label: {
                HStack {
                    // Tamanho mínimo fixo — sem isso, trocar pro texto mais longo (que quebra em
                    // duas linhas) fazia o menu inteiro, e o campo de busca ao lado (que ocupa o
                    // espaço sobrando), pularem de tamanho no meio da animação de seleção.
                    Text(filterLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 130, minHeight: 32)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
        }
    }

    private var filterLabel: String {
        switch filter {
        case .all: "todos os anúncios"
        case .discountOnly: "anúncios que pedem desconto"
        }
    }

    /// Refaz o filtro/ordenação inteiro de uma vez só, guardando o resultado em `filteredItems` —
    /// chamado só quando `filter`, `runner.items` ou `searchText` mudam de verdade, não a cada
    /// leitura (ver os `@State`/`onChange` no topo do arquivo e em `body`).
    /// A busca por título consulta o SwiftData (`runner.searchProductIDs(matching:)` — `#Predicate`
    /// + `fetchLimit`, sem `JSONDecoder`), mas só pra saber QUAIS ids batem — os itens em si sempre
    /// vêm de `runner.items` (a lista ao vivo), nunca reconstruídos a partir do que foi persistido:
    /// status/exposição salvos nunca refletem uma megafonagem em andamento (só existe ao vivo aqui),
    /// então buscar aceitando esse "atraso" mostraria status errado de propósito. Ver
    /// `MegaphoneItemRecord`/`MegaphoneRunner.searchProductIDs(matching:)`.
    private func recomputeFilteredItems() {
        let items: [MegaphoneItem]
        switch filter {
        case .all:
            items = runner.items
        case .discountOnly:
            // Crescente pelo desconto que o megafone está sugerindo (o valor em laranja na row) —
            // quem precisa de um corte menor pra alcançar exposição máxima aparece primeiro.
            items = runner.items
                .filter { $0.exposure?.kind.requiresDiscountDecision == true }
                .sorted { ($0.computedDiscountPercent ?? 0) < ($1.computedDiscountPercent ?? 0) }
        }
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            filteredItems = items
            return
        }
        let matchedIDs = Set(runner.searchProductIDs(matching: trimmedSearch))
        filteredItems = items.filter { matchedIDs.contains($0.id) }
    }

    @ViewBuilder
    private var productList: some View {
        if runner.items.isEmpty {
            ContentUnavailableView(
                "nenhum produto na fila",
                systemImage: "shippingbox",
                description: Text("toque em megafonar para buscar os produtos da sua loja.")
            )
            .frame(maxHeight: .infinity)
        } else if filteredItems.isEmpty {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "nenhum produto pede desconto agora",
                    systemImage: "checkmark.circle",
                    description: Text("toque em \"todos os anúncios\" pra ver a fila inteira.")
                )
                .frame(maxHeight: .infinity)
            }
        } else {
            ScrollViewReader { proxy in
                List(filteredItems) { item in
                    MegaphoneRowView(
                        item: item,
                        runner: runner,
                        account: account,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(item.id),
                        onToggleSelection: { toggleSelection(itemID: item.id) }
                    )
                    .id(item.id)
                }
                .listStyle(.plain)
                .onChange(of: runner.currentItemID) { _, newValue in
                    guard isFollowing, let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }
}
