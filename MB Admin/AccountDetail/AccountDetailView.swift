import SwiftUI

/// Detalhe de uma conta: o nome (e quantos megafones/erros) na barra de navegação, o seletor de
/// abas logo abaixo (com a fileira de filtros da aba, quando ela tem) e o conteúdo da aba. A aba
/// "publicados" (megafonar, busca, seleção múltipla — e a toolbar/barra de baixo que vêm com eles)
/// vive em `AccountPublishedTabView` — o estado dela que também importa aqui (esconder o seletor de
/// abas durante a seleção, o filtro das cápsulas, ou sobreviver a trocar de aba e voltar) fica com
/// esta view, passado pra lá por `@Binding`.
///
/// Identidade estável entre contas de propósito — `AccountsListView` NÃO dá `.id(account.id)` a
/// esta view. Um `.id()` aqui forçaria o SwiftUI a destruir e reconstruir a árvore inteira (incluindo
/// `AccountPublishedTabView`, com sua lista de até milhares de produtos) toda vez que a conta
/// selecionada na barra lateral muda — perceptível como travamento ao checar 3 contas megafonando ao
/// mesmo tempo. `filter` (e o estado de `AccountPublishedTabView`) vivia antes em `@AppStorage` com
/// chave dinâmica por conta, mas isso só funciona de verdade com identidade nova a cada conta (o
/// "storage" de `@AppStorage` gruda na identidade da view, não na chave calculada no `init` mais
/// recente) — por isso agora é `@State` simples, recarregado manualmente do `UserDefaults` em
/// `onChange(of: account.id)`. `InactiveProductsListView`/`SmartPriceProductsListView` (as abas
/// "inativos"/"preço esperto") seguem o mesmo raciocínio internamente, sem `.id(account.id)`.
///
/// `selectedTab` de propósito NÃO é lembrado por conta (era antes, com uma chave por conta no
/// `UserDefaults` — removido a pedido do usuário): o `switch selectedTab` abaixo, ao trocar de ramo,
/// destrói e reconstrói a subview daquele ramo do zero — igual ao que `.id()` faria. Se `selectedTab`
/// fosse recarregado a cada troca de conta, trocar para uma conta que estava numa aba diferente
/// disparava exatamente essa reconstrução. Como `@State` comum (não per-account), `selectedTab` só
/// muda quando o usuário toca no segmented control — trocar de conta não troca mais de ramo sozinho.
struct AccountDetailView: View {
    let account: AccountSession

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Aba e filtro escolhidos, lembrados por conta — ver o comentário no topo do arquivo sobre por
    /// que não são mais `@AppStorage`.
    @State private var selectedTab: DetailTab = .published
    @State private var filter: AccountProductFilter = .all
    /// Filtro de status da aba "sem preço esperto" — mesmo esquema de `filter` (por conta, recarregado
    /// em `loadState`), e não `@AppStorage`, pelo motivo do comentário no topo do arquivo.
    @State private var smartPriceFilter = SmartPriceStatusFilter.defaultFilter
    /// Resumo de "ativar em N" que a aba "sem preço esperto" manda pro subtítulo no iPhone.
    @State private var smartPriceActivationSummary = ""
    @State private var searchText = ""
    /// Quando ativo, a lista rola sozinha até o produto que está sendo megafonado no momento.
    @State private var isFollowing = true
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []

    private var runner: MegaphoneRunner { account.runner }
    private var keepAlive: MegaphoneKeepAlive { account.keepAlive }
    private var isCompact: Bool { horizontalSizeClass != .regular }

    private enum DetailTab: String, CaseIterable {
        case published = "publicados"
        case inactive = "inativos"
        case smartPrice = "sem preço esperto"
    }

    init(account: AccountSession) {
        self.account = account
    }

    /// Recarrega os filtros do que essa conta tinha guardado (ou o padrão, se nunca guardou nada) e
    /// zera o resto — mesmo efeito que reconstruir a view do zero tinha antes, só que sem destruir
    /// `AccountPublishedTabView`/a lista de produtos por baixo. `selectedTab` fica de fora de
    /// propósito — ver o comentário no topo do arquivo sobre por que ele não é mais lembrado por
    /// conta.
    private func loadState(for accountID: EnjoeiAccountID) {
        filter = UserDefaults.standard.string(forKey: AccountProductFilter.storageKey(for: accountID))
            .flatMap(AccountProductFilter.init) ?? .all
        smartPriceFilter = UserDefaults.standard.string(forKey: SmartPriceStatusFilter.storageKey(for: accountID))
            .flatMap(SmartPriceStatusFilter.init) ?? .defaultFilter
        searchText = ""
        isFollowing = true
        isSelecting = false
        selectedIDs = []
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .published:
                AccountPublishedTabView(
                    account: account,
                    filter: $filter,
                    searchText: $searchText,
                    isSelecting: $isSelecting,
                    selectedIDs: $selectedIDs,
                    isFollowing: $isFollowing
                )
            case .inactive:
                inactiveContent
            case .smartPrice:
                smartPriceContent
            }
        }
        // Barra presa no topo (em vez de só empilhada em cima da lista): a lista rola por baixo
        // do seletor, com o efeito de borda do sistema, como embaixo da barra de navegação.
        .floatingTopBar {
            // Selecionando, a tela inteira é sobre a seleção — trocar de aba (ou de filtro) no meio
            // largaria ela pela metade.
            if !isSelecting {
                VStack(alignment: .leading, spacing: 0) {
                    tabPicker
                    filterChips
                }
            }
        }
        .animation(.default, value: isSelecting)
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
        .onChange(of: filter) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: AccountProductFilter.storageKey(for: account.id))
        }
        .onChange(of: smartPriceFilter) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: SmartPriceStatusFilter.storageKey(for: account.id))
        }
        // Busca e seleção são de uma aba só — a lista da outra aba não tem os mesmos produtos.
        .onChange(of: selectedTab) { _, _ in
            searchText = ""
            isSelecting = false
            selectedIDs = []
        }
        // Selecionando, o título conta a seleção — como título de verdade, não um item `.principal`
        // na toolbar: no iPad, com o título grande à esquerda, o `.principal` nem aparece.
        .navigationTitle(isSelecting ? selectionTitle : account.user.name)
        .navigationSubtitleIfAvailable(subtitle)
        // iPad/Mac: título grande alinhado à esquerda, com a busca e os botões na mesma faixa;
        // iPhone: título centralizado, como no resto do sistema.
        .toolbarTitleDisplayMode(isCompact ? .inline : .inlineLarge)
        .toolbar {
            // A aba "publicados" monta o próprio recarregar (junto da seleção, ver
            // `AccountPublishedTabView`); nas outras ele fica aqui — no iPhone também, desde que os
            // filtros saíram da barra de cima (o recarregar do iPhone morava dentro do menu de
            // filtro). Selecionando, sai da barra — recarregar trocaria a lista por baixo da seleção.
            if showsReloadButton {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Sempre mexe nos publicados também — bloqueado em qualquer aba enquanto o
                        // megafone está rodando, não só na de publicados. Checado aqui também porque
                        // no Mac o botão nunca fica desabilitado (ver `ToolbarItemDisabled`).
                        guard !runner.isRunning else { return }
                        account.reloadAllProducts()
                    } label: {
                        Label("recarregar produtos", systemImage: "arrow.clockwise")
                    }
                    .toolbarItemDisabled(runner.isRunning)
                }
            }
        }
        // Entrar na conta (primeira vez OU troca na barra lateral, já que a identidade desta view
        // não muda mais — ver `onChange(of: account.id)`) já busca sozinho os produtos publicados
        // (com a exposição de cada um, pra seção "pedem desconto" já vir pronta) e os inativos, em
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

    private var showsReloadButton: Bool {
        !isSelecting && selectedTab != .published
    }

    private var selectionTitle: String {
        switch selectedIDs.count {
        case 0: "selecionar produtos"
        case 1: "1 selecionado"
        default: "\(selectedIDs.count) selecionados"
        }
    }

    private var tabPicker: some View {
        Picker("aba", selection: $selectedTab) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Text(tabLabel(tab)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: isCompact ? .infinity : 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Os filtros da aba à vista, em cápsulas — no conteúdo da barra presa no topo, não na toolbar
    /// (ver `FilterChipBar`). "inativos" não tem filtro.
    @ViewBuilder
    private var filterChips: some View {
        switch selectedTab {
        case .published:
            FilterChipBar(options: publishedFilterOptions, selection: $filter, horizontalPadding: isCompact ? 16 : 24)
                .padding(.bottom, 4)
        case .smartPrice:
            FilterChipBar(options: smartPriceFilterOptions, selection: $smartPriceFilter, horizontalPadding: isCompact ? 16 : 24)
                .padding(.bottom, 4)
        case .inactive:
            EmptyView()
        }
    }

    /// As contagens vêm de `progressSnapshot` (o resumo em lote), não de `runner.items` — mesmo
    /// cuidado de `tabLabel`: ler `items` aqui prenderia esta view a reavaliar a cada produto
    /// megafonado. Contam a loja inteira, sem a busca, como o rótulo da aba.
    private var publishedFilterOptions: [FilterChipOption<AccountProductFilter>] {
        let snapshot = runner.progressSnapshot
        return [
            FilterChipOption(value: .all, label: AccountProductFilter.all.label, count: snapshot.itemsCount),
            FilterChipOption(
                value: .discountOnly,
                label: AccountProductFilter.discountOnly.label,
                count: snapshot.discountDecisionCount,
                dotColor: .statusDecision
            )
        ]
    }

    /// Cada status com quantos produtos ainda estão sem preço esperto (sem a busca, como o rótulo da
    /// aba) e a bolinha na cor que o Enjoei manda pra ele.
    private var smartPriceFilterOptions: [FilterChipOption<SmartPriceStatusFilter>] {
        let loader = account.smartPriceProductsLoader
        let products = SmartPriceStatusFilter.stillWithoutSmartPrice(
            loader.items,
            activationStatuses: loader.activationStatuses
        )
        return SmartPriceStatusFilter.allCases.map { status in
            FilterChipOption(
                value: status,
                label: status.label,
                count: status.count(in: products),
                dotColor: Color(hex: status.dotColorHex(in: products))
            )
        }
    }

    /// "351 megafones · 2 com erro" — no iPad/Mac, com o @apelido na frente. No iPhone, sem erro
    /// nenhum fica só "351 megafones": embaixo do nome, ao lado dos botões, o texto inteiro não
    /// cabe no tamanho de letra do app. Selecionando, o título vira "N selecionados" e aqui fica
    /// só a busca que continua filtrando a lista (o campo some durante a seleção), se houver.
    ///
    /// `progressSnapshot.totalSucceeded/.totalFailed`, não `runner.totalSucceeded/.totalFailed`
    /// direto — mesmos campos, mas os direto no runner mudam a cada produto megafonado (até 1500+
    /// vezes por rodada), prendendo o `body` inteiro (toolbar, aba selecionada) a reavaliar nessa
    /// frequência; o snapshot já é a versão em lote pra isso.
    private var subtitle: String {
        guard !isSelecting else {
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return search.isEmpty ? "" : "buscando \"\(search)\""
        }
        // No iPhone, a aba "sem preço esperto" não tem a barra de vidro de "ativar em N" — o resumo
        // ("6 produtos com preço atual · 1 bloqueado") fica aqui, acima da lista.
        if isCompact, selectedTab == .smartPrice, !smartPriceActivationSummary.isEmpty {
            return smartPriceActivationSummary
        }
        let snapshot = runner.progressSnapshot
        let megaphones = "\(snapshot.totalSucceeded.formatted()) megafones"
        let errors = "\(snapshot.totalFailed.formatted()) com erro"
        if isCompact {
            return snapshot.totalFailed > 0 ? "\(megaphones) · \(errors)" : megaphones
        }
        return "@\(account.user.nickname) · \(megaphones) · \(errors)"
    }

    // Identidade estável entre contas, igual `AccountPublishedTabView` (ver o comentário no topo do
    // arquivo) — cada uma zera seu próprio estado local internamente via
    // `onChange(of: account.id, initial: true)`, sem precisar de `.id(account.id)` aqui.
    private var inactiveContent: some View {
        InactiveProductsListView(
            account: account,
            searchText: $searchText,
            isSelecting: $isSelecting,
            selectedIDs: $selectedIDs
        )
    }

    private var smartPriceContent: some View {
        SmartPriceProductsListView(
            account: account,
            searchText: $searchText,
            isSelecting: $isSelecting,
            selectedIDs: $selectedIDs,
            statusFilter: $smartPriceFilter,
            compactActivationSummary: $smartPriceActivationSummary
        )
    }

    /// No iPhone, só o nome da aba — os três rótulos com quantidade não cabem lado a lado. No
    /// iPad/Mac, a quantidade aparece depois de já ter carregado (produtos publicados ou inativos)
    /// — antes disso, o rótulo fica sem número, sem sugerir uma contagem de "0" que ainda não é real.
    private func tabLabel(_ tab: DetailTab) -> String {
        guard !isCompact else { return tab.rawValue }
        switch tab {
        case .published:
            // `progressSnapshot.itemsCount`, não `runner.items.count` direto — ler `items` aqui
            // prenderia esta view (dona do toolbar/segmented control) a reavaliar a cada produto
            // megafonado, mesmo só lendo `.count`/`.isEmpty` (O(1)).
            let itemsCount = runner.progressSnapshot.itemsCount
            guard itemsCount > 0 else { return tab.rawValue }
            return "\(tab.rawValue) (\(itemsCount.formatted()))"
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
