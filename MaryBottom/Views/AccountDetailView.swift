import SwiftUI

/// Detalhe de uma conta: identifica o usuário e conduz o megafone da loja dele.
struct AccountDetailView: View {
    let account: AccountSession

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AccountsStore.self) private var accountsStore
    /// Quantas vezes repetir a lista. Fica guardado entre execuções do app (0 = infinito). Por
    /// conta: com contas rodando em paralelo, uma preferência global faria trocar a velocidade de
    /// uma afetar silenciosamente as outras já em andamento.
    @AppStorage private var storedRounds: Int
    /// Intervalo entre um megafone e o próximo, em milissegundos.
    @AppStorage private var storedSpeed: Int

    @State private var filter: ProductFilter = .all
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    /// Quando ativo, a lista rola sozinha até o produto que está sendo megafonado no momento.
    @State private var isFollowing = true
    @State private var selectedTab: DetailTab = .published
    /// Seleção múltipla, disponível nos dois filtros — a ação em massa muda conforme o filtro
    /// atual: aplicar desconto em "pede desconto" (única ação possível ali), ou
    /// repostar/inativar/apagar (escolhido pelo usuário) em "todos os anúncios".
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var bulkAction: BulkAction = .repost
    @State private var isConfirmingBulkApply = false
    @State private var isConfirmingBulkRepost = false
    @State private var isConfirmingBulkDelete = false
    @State private var isConfirmingBulkInactivate = false

    private var runner: MegaphoneRunner { account.runner }
    private var keepAlive: MegaphoneKeepAlive { account.keepAlive }

    private enum ProductFilter {
        case all
        case discountOnly
    }

    /// Ação escolhida pro botão de confirmar da seleção múltipla, no filtro "todos os anúncios" —
    /// "pede desconto" não usa isso, só tem uma ação possível ali (aplicar desconto).
    private enum BulkAction: CaseIterable {
        case repost
        case inactivate
        case delete

        var label: String {
            switch self {
            case .repost: "repostar"
            case .inactivate: "inativar"
            case .delete: "apagar"
            }
        }

        /// Mesmos ícones do menu "..." de cada linha, pro botão de confirmar em massa reconhecer
        /// de longe (junto com a cor) qual ação está selecionada.
        var systemImage: String {
            switch self {
            case .repost: "doc.on.doc.fill"
            case .inactivate: "archivebox.fill"
            case .delete: "trash.fill"
            }
        }

        var tint: Color {
            switch self {
            case .repost: .accentColor
            case .inactivate: .secondary
            case .delete: .red
            }
        }
    }

    private enum DetailTab: String, CaseIterable {
        case published = "publicados"
        case inactive = "inativos"
    }

    init(account: AccountSession) {
        self.account = account
        _storedRounds = AppStorage(wrappedValue: 1, "megaphone.rounds.\(account.id)")
        _storedSpeed = AppStorage(wrappedValue: MegaphoneSpeed.standard.milliseconds, "megaphone.speed.\(account.id)")
    }

    private var rounds: MegaphoneRounds { MegaphoneRounds(rawValue: storedRounds) }
    private var speed: MegaphoneSpeed { MegaphoneSpeed(milliseconds: storedSpeed) }

    var body: some View {
        VStack(spacing: 16) {
            UserHeaderView(
                user: account.user,
                megaphoneCount: runner.totalSucceeded,
                errorCount: runner.totalFailed
            )

            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tabLabel(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .published:
                publishedContent
            case .inactive:
                inactiveContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // Enquanto roda, o app segura a tela acesa e um áudio silencioso para não ser congelado
        // ao você trocar de app.
        .onChange(of: runner.isRunning) { _, isRunning in
            isRunning ? keepAlive.start() : keepAlive.stop()
        }
        // Vale mudar o intervalo no meio da rodada: o laço lê o valor a cada produto.
        .onChange(of: storedSpeed) { _, milliseconds in
            runner.delayBetweenProducts = MegaphoneSpeed(milliseconds: milliseconds).duration
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: keepAlive.applicationBecameActive()
            case .inactive, .background: keepAlive.applicationWentToBackground()
            @unknown default: break
            }
        }
        // A seleção só faz sentido dentro do filtro "pede desconto" — trocar de filtro (ou sair
        // dele) com itens marcados deixaria a seleção "invisível" mas ainda contando pro botão de
        // aplicar em massa.
        .onChange(of: filter) { _, _ in
            isSelecting = false
            selectedIDs.removeAll()
            bulkAction = .repost
        }
        .navigationTitle(account.user.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Recarrega as duas abas de uma vez, não só a que está na tela agora — publicados
                // busca a loja de novo do zero, inativos refaz a raspagem das páginas de novo (é
                // o único jeito de tentar de novo manualmente, além do botão "tentar de novo" que
                // só aparece quando dá erro de verdade).
                Button {
                    runner.reload(sellerID: account.user.id)
                    account.inactiveProductsLoader.load()
                } label: {
                    // Círculo com tamanho fixo (em vez do bezel padrão de toolbar, que no Mac
                    // idiom otimizado saía pequeno e num "squircle" em vez de redondo) — largura e
                    // altura iguais garantem o círculo perfeito independente da fonte do sistema.
                    Label("recarregar produtos", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(.quaternary, in: .circle)
                }
                .buttonStyle(.plain)
                // Sempre mexe nos publicados agora, mesmo vendo "inativos" — desabilita em
                // qualquer aba enquanto o megafone está rodando, não só na de publicados.
                .disabled(runner.isRunning)
            }
            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }
            // "Acompanhar" só faz sentido pro fluxo de megafonar (publicados) — na aba de
            // inativos não tem nada acontecendo em segundo plano pra seguir o progresso.
            if selectedTab == .published {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isFollowing.toggle()
                    } label: {
                        Label(
                            "acompanhar",
                            systemImage: isFollowing ? "location.fill" : "location"
                        )
                    }
                    .tint(isFollowing ? .accentColor : .secondary)
                }
            }
        }
        // Ao entrar na conta pela primeira vez, já busca sozinho os produtos publicados (com a
        // exposição de cada um, pro filtro "pede desconto" já vir pronto) e os inativos, em
        // paralelo — sem começar a megafonar por conta própria (isso continua exigindo o toque
        // explícito no botão "megafonar", em nenhuma hipótese disparado sozinho por aqui).
        .task {
            if runner.items.isEmpty, !runner.isRunning {
                runner.load(sellerID: account.user.id)
            }
            if account.inactiveProductsLoader.items.isEmpty, account.inactiveProductsLoader.phase == .idle {
                account.inactiveProductsLoader.load()
            }
        }
    }

    @ViewBuilder
    private var publishedContent: some View {
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

    /// Seleção múltipla da lista de publicados — a ação em massa muda conforme o filtro atual:
    /// aplicar o desconto sugerido em "pede desconto" (só esses itens têm o que aplicar), ou
    /// repostar em "todos os anúncios" (mesma ação do menu "..." de cada linha, em lote).
    @ViewBuilder
    private var selectionBar: some View {
        if !filteredItems.isEmpty {
            HStack {
                Button(isSelecting ? "cancelar seleção" : "selecionar") {
                    isSelecting.toggle()
                    if !isSelecting {
                        selectedIDs.removeAll()
                        bulkAction = .repost
                    }
                }
                .buttonStyle(.bordered)

                if isSelecting {
                    Button(isAllFilteredSelected ? "desmarcar todos" : "selecionar todos") {
                        toggleSelectAllFiltered()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if isSelecting, !selectedIDs.isEmpty {
                    bulkActionButton
                }
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

    @ViewBuilder
    private var bulkActionButton: some View {
        switch filter {
        case .discountOnly:
            Button("aplicar desconto em \(selectedIDs.count)") {
                isConfirmingBulkApply = true
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        case .all:
            bulkActionSelector
        }
    }

    /// Seletor repostar/inativar/apagar + botão de confirmar, pro filtro "todos os anúncios" —
    /// cada ação tem sua própria confirmação antes de entrar na fila (`isConfirmingBulkRepost`/
    /// `isConfirmingBulkInactivate`/`isConfirmingBulkDelete`, todas na `selectionBar`).
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
                case .inactivate: isConfirmingBulkInactivate = true
                case .delete: isConfirmingBulkDelete = true
                }
            } label: {
                Image(systemName: bulkAction.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(bulkAction.tint, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(bulkAction.label) \(selectedIDs.count) produtos")
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

    private var inactiveContent: some View {
        InactiveProductsListView(account: account)
    }

    /// Só mostra a quantidade depois de já ter dado carregado (produtos publicados ou inativos) —
    /// antes disso, o rótulo fica sem número, sem sugerir uma contagem de "0" que ainda não é real.
    private func tabLabel(_ tab: DetailTab) -> String {
        switch tab {
        case .published:
            guard !runner.items.isEmpty else { return tab.rawValue }
            return "\(tab.rawValue) (\(runner.items.count.formatted()))"
        case .inactive:
            let loader = account.inactiveProductsLoader
            guard !loader.items.isEmpty || loader.phase == .finished else { return tab.rawValue }
            return "\(tab.rawValue) (\(loader.items.count.formatted()))"
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
    }

    @ViewBuilder
    private var filterPicker: some View {
        if !runner.items.isEmpty {
            Menu {
                Picker("filtro", selection: $filter) {
                    Text("todos os anúncios").tag(ProductFilter.all)
                    Text("anúncios que pedem desconto").tag(ProductFilter.discountOnly)
                }
                .pickerStyle(.inline)
            } label: {
                HStack {
                    Text(filterLabel)
                        .foregroundStyle(.secondary)
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

    private var filteredItems: [MegaphoneItem] {
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
        guard !trimmedSearch.isEmpty else { return items }
        return items.filter { $0.product.title.localizedCaseInsensitiveContains(trimmedSearch) }
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
