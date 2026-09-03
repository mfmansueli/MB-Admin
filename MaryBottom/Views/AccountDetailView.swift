import SwiftUI

/// Detalhe de uma conta: identifica o usuário e conduz o megafone da loja dele. A aba "publicados"
/// (megafonar, busca, filtro, seleção múltipla) vive em `AccountPublishedTabView` — o estado dela
/// que também importa aqui (pro toolbar, ou pra sobreviver a trocar de aba e voltar) fica com esta
/// view, passado pra lá por `@Binding`.
struct AccountDetailView: View {
    let account: AccountSession

    @Environment(\.scenePhase) private var scenePhase

    @State private var filter: AccountProductFilter = .all
    @State private var searchText = ""
    /// Quando ativo, a lista rola sozinha até o produto que está sendo megafonado no momento.
    @State private var isFollowing = true
    @State private var selectedTab: DetailTab = .published
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var bulkAction: AccountBulkAction = .repost
    @State private var discountBulkAction: AccountDiscountBulkAction = .applyDiscount

    private var runner: MegaphoneRunner { account.runner }
    private var keepAlive: MegaphoneKeepAlive { account.keepAlive }

    private enum DetailTab: String, CaseIterable {
        case published = "publicados"
        case inactive = "inativos"
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
}
