import SwiftUI

/// Detalhe de uma conta: identifica o usuário e conduz o megafone da loja dele. A aba "publicados"
/// (megafonar, busca, filtro, seleção múltipla) vive em `AccountPublishedTabView` — o estado dela
/// que também importa aqui (pro toolbar, ou pra sobreviver a trocar de aba e voltar) fica com esta
/// view, passado pra lá por `@Binding`.
///
/// Identidade estável entre contas de propósito — `AccountsListView` NÃO dá `.id(account.id)` a
/// esta view. Um `.id()` aqui forçaria o SwiftUI a destruir e reconstruir a árvore inteira (incluindo
/// `AccountPublishedTabView`, com sua lista de até milhares de produtos) toda vez que a conta
/// selecionada na barra lateral muda — perceptível como travamento ao checar 3 contas megafonando ao
/// mesmo tempo. `selectedTab`/`filter` (e o estado de `AccountPublishedTabView`) viviam antes em
/// `@AppStorage` com chave dinâmica por conta, mas isso só funciona de verdade com identidade nova a
/// cada conta (o "storage" de `@AppStorage` gruda na identidade da view, não na chave calculada no
/// `init` mais recente) — por isso agora são `@State` simples, recarregados manualmente do
/// `UserDefaults` em `onChange(of: account.id)`. As abas "inativos"/"preço esperto" continuam com
/// `.id(account.id)` (ver `inactiveContent`/`smartPriceContent`) — não são a tela ativa durante o
/// megafone, então não vale o risco de replicar esse mesmo tratamento nelas agora.
struct AccountDetailView: View {
    let account: AccountSession

    @Environment(\.scenePhase) private var scenePhase

    /// Aba e filtro escolhidos, lembrados por conta — ver o comentário no topo do arquivo sobre por
    /// que não são mais `@AppStorage`.
    @State private var selectedTab: DetailTab = .published
    @State private var filter: AccountProductFilter = .all
    @State private var searchText = ""
    /// Quando ativo, a lista rola sozinha até o produto que está sendo megafonado no momento.
    @State private var isFollowing = true
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var bulkAction: AccountBulkAction = .repost
    @State private var discountBulkAction: AccountDiscountBulkAction = .applyDiscount

    private var runner: MegaphoneRunner { account.runner }
    private var keepAlive: MegaphoneKeepAlive { account.keepAlive }

    private enum DetailTab: String, CaseIterable {
        case published = "publicados"
        case inactive = "inativos"
        case smartPrice = "sem preço esperto"
    }

    init(account: AccountSession) {
        self.account = account
    }

    private func selectedTabKey(_ accountID: EnjoeiAccountID) -> String {
        "accountDetail.selectedTab.\(accountID)"
    }

    private func filterKey(_ accountID: EnjoeiAccountID) -> String {
        "accountDetail.filter.\(accountID)"
    }

    /// Recarrega `selectedTab`/`filter` do que essa conta tinha guardado (ou o padrão, se nunca
    /// guardou nada) e zera o resto — mesmo efeito que reconstruir a view do zero tinha antes, só
    /// que sem destruir `AccountPublishedTabView`/a lista de produtos por baixo.
    private func loadState(for accountID: EnjoeiAccountID) {
        selectedTab = UserDefaults.standard.string(forKey: selectedTabKey(accountID))
            .flatMap(DetailTab.init) ?? .published
        filter = UserDefaults.standard.string(forKey: filterKey(accountID))
            .flatMap(AccountProductFilter.init) ?? .all
        searchText = ""
        isFollowing = true
        isSelecting = false
        selectedIDs = []
        bulkAction = .repost
        discountBulkAction = .applyDiscount
    }

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
                AccountPublishedTabView(
                    account: account,
                    filter: $filter,
                    searchText: $searchText,
                    isSelecting: $isSelecting,
                    selectedIDs: $selectedIDs,
                    bulkAction: $bulkAction,
                    discountBulkAction: $discountBulkAction,
                    isFollowing: $isFollowing
                )
            case .inactive:
                inactiveContent
            case .smartPrice:
                smartPriceContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // Enquanto roda, o app segura a tela acesa e um áudio silencioso para não ser congelado
        // ao você trocar de app.
        .onChange(of: runner.isRunning) { _, isRunning in
            isRunning ? keepAlive.start() : keepAlive.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: keepAlive.applicationBecameActive()
            case .inactive, .background: keepAlive.applicationWentToBackground()
            @unknown default: break
            }
        }
        // `initial: true` cobre tanto a primeira vez que esta view aparece quanto cada troca de
        // conta na barra lateral — sem identidade nova por conta, é o único gatilho que sobrou pra
        // recarregar/zerar o estado (ver `loadState`).
        .onChange(of: account.id, initial: true) { _, newAccountID in
            loadState(for: newAccountID)
        }
        .onChange(of: selectedTab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedTabKey(account.id))
        }
        .onChange(of: filter) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: filterKey(account.id))
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
                    account.smartPriceProductsLoader.load()
                } label: {
                    // Círculo com tamanho mínimo (em vez do bezel padrão de toolbar, que no Mac
                    // idiom otimizado saía pequeno e num "squircle" em vez de redondo) — largura e
                    // altura mínimas iguais garantem o círculo perfeito independente da fonte do
                    // sistema, sem impor um frame fixo que brigue com o dimensionamento próprio do
                    // `_UIButtonBarButton` por trás do item de toolbar no Mac Catalyst (`.frame`
                    // fixo aqui gerava "Unable to simultaneously satisfy constraints" toda vez que
                    // este botão re-renderizava — coisa frequente durante o megafone, já que o
                    // corpo da view lê `runner.totalSucceeded`/`totalFailed`/`items.count`).
                    Label("recarregar produtos", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 34, minHeight: 34)
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
        // Entrar na conta (primeira vez OU troca na barra lateral, já que a identidade desta view
        // não muda mais — ver `onChange(of: account.id)`) já busca sozinho os produtos publicados
        // (com a exposição de cada um, pro filtro "pede desconto" já vir pronto) e os inativos, em
        // paralelo — sem começar a megafonar por conta própria (isso continua exigindo o toque
        // explícito no botão "megafonar", em nenhuma hipótese disparado sozinho por aqui).
        .task(id: account.id) {
            if runner.items.isEmpty, !runner.isRunning {
                runner.load(sellerID: account.user.id)
            }
            if account.inactiveProductsLoader.items.isEmpty, account.inactiveProductsLoader.phase == .idle {
                account.inactiveProductsLoader.load()
            }
            if account.smartPriceProductsLoader.items.isEmpty, account.smartPriceProductsLoader.phase == .idle {
                account.smartPriceProductsLoader.load()
            }
        }
    }

    // `.id(account.id)`: ao contrário de `AccountPublishedTabView` (ver o comentário no topo do
    // arquivo), estas duas não são a tela ativa durante o megafone — mantém o mesmo tratamento
    // (destruir e reconstruir ao trocar de conta) que a `AccountDetailView` inteira tinha antes,
    // sem risco de vazar estado entre contas.
    private var inactiveContent: some View {
        InactiveProductsListView(account: account)
            .id(account.id)
    }

    private var smartPriceContent: some View {
        SmartPriceProductsListView(account: account)
            .id(account.id)
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
        case .smartPrice:
            let loader = account.smartPriceProductsLoader
            guard !loader.items.isEmpty || loader.phase == .finished else { return tab.rawValue }
            return "\(tab.rawValue) (\(loader.items.count.formatted()))"
        }
    }
}
