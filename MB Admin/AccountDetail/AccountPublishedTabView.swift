import SwiftUI

/// Aba "publicados" de `AccountDetailView`: megafonar, busca, seleção múltipla e a lista de produtos
/// publicados, dividida em "pedem desconto" e "todos os anúncios". O estado que também importa pro
/// resto de `AccountDetailView` (esconder o seletor de abas durante a seleção, o filtro escolhido na
/// fileira de cápsulas de lá, ou sobreviver a trocar pra aba "inativos" e voltar) continua lá,
/// passado aqui por `@Binding`.
///
/// É esta view (não `AccountDetailView`) que monta a toolbar, a busca e a barra de baixo da tela:
/// tudo isso só faz sentido nesta aba, e sai junto com ela ao trocar pra "inativos"/"sem preço
/// esperto". Parado, a barra de baixo é a do sistema (repetições · intervalo, busca, megafonar);
/// com uma rodada em aberto, `MegaphoneRunPanel` toma o lugar dela; selecionando,
/// `SelectionActionBar`.
struct AccountPublishedTabView: View {
    let account: AccountSession

    @Binding var filter: AccountProductFilter
    @Binding var searchText: String
    @Binding var isSelecting: Bool
    @Binding var selectedIDs: Set<Int>
    @Binding var isFollowing: Bool

    @Environment(AccountsStore.self) private var accountsStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Quantas vezes repetir a lista. Fica guardado entre execuções do app (0 = infinito). Por
    /// conta: com contas rodando em paralelo, uma preferência global faria trocar a velocidade de
    /// uma afetar silenciosamente as outras já em andamento.
    ///
    /// `@State` simples, não `@AppStorage` com chave dinâmica — esta view tem identidade estável
    /// entre contas agora (ver o comentário no topo de `AccountDetailView.swift`), e `@AppStorage`
    /// só recalcula a chave de verdade quando a identidade da view muda. Lido/gravado manualmente no
    /// `UserDefaults` em `onChange(of: account.id)`/`onChange(of: storedRounds)`/
    /// `onChange(of: storedSpeed)`, abaixo.
    @State private var storedRounds = 1
    @State private var storedSpeed = MegaphoneSpeed.standard.milliseconds

    /// Ação em massa esperando confirmação no alerta — `nil` sem alerta na tela.
    @State private var pendingBulkAction: PublishedBulkAction?
    /// O "aplicar nos N" do cabeçalho de "pedem desconto" esperando confirmação — `nil` sem alerta.
    @State private var pendingDiscountBatch: PendingDiscountBatch?
    /// Cache das seções (ver `recomputeSections`) — sem isso, cada leitura (lista, "todos",
    /// contagem) refiltrava/reordenava a lista inteira de publicados do zero, várias vezes por
    /// digitação.
    @State private var sections = PublishedProductSections()
    @State private var collapsedSections: Set<PublishedProductSections.Kind> = []
    @State private var searchDebounceTask: Task<Void, Never>?

    private var runner: MegaphoneRunner { account.runner }
    private var isCompact: Bool { horizontalSizeClass != .regular }

    init(
        account: AccountSession,
        filter: Binding<AccountProductFilter>,
        searchText: Binding<String>,
        isSelecting: Binding<Bool>,
        selectedIDs: Binding<Set<Int>>,
        isFollowing: Binding<Bool>
    ) {
        self.account = account
        _filter = filter
        _searchText = searchText
        _isSelecting = isSelecting
        _selectedIDs = selectedIDs
        _isFollowing = isFollowing
    }

    private var rounds: MegaphoneRounds { MegaphoneRounds(rawValue: storedRounds) }
    private var speed: MegaphoneSpeed { MegaphoneSpeed(milliseconds: storedSpeed) }

    private func roundsKey(_ accountID: EnjoeiAccountID) -> String { "megaphone.rounds.\(accountID)" }
    private func speedKey(_ accountID: EnjoeiAccountID) -> String { "megaphone.speed.\(accountID)" }

    /// Rodada em aberto — inclusive esperando a vez na fila ou só buscando a loja: em todos esses
    /// casos o painel do megafone fica no lugar da barra de "megafonar".
    private var isRoundOpen: Bool { runner.phase.isActive || runner.isRunning }

    var body: some View {
        productList
            .floatingBottomBar { bottomBar }
            .toolbar { toolbarContent }
            // A busca só existe parada e fora da seleção — com o painel do megafone ou a barra da
            // seleção embaixo, no iPhone a lupa ficava sozinha por baixo deles (esconder a barra
            // de baixo do sistema não esconde a busca minimizada). Num fundo vazio, não na lista:
            // pôr/tirar `.searchable` da própria lista trocaria a identidade dela, e a rolagem
            // voltaria pro topo a cada megafonar/selecionar.
            .background {
                if !isRoundOpen, !isSelecting {
                    Color.clear
                        .searchable(text: $searchText, prompt: "buscar por nome")
                        .modifier(MinimizedSearchOnCompact(isCompact: isCompact))
                }
            }
            // Selecionando, sair da tela pela seta de voltar largaria a seleção pela metade — o
            // único caminho de saída é o "concluir".
            .navigationBarBackButtonHidden(isSelecting)
            // Com o painel do megafone ou a barra da seleção no lugar, a barra do sistema some de
            // vez — sem isso, no iPhone a lupa da busca ficava sozinha embaixo deles.
            .toolbar(isRoundOpen || isSelecting ? .hidden : .automatic, for: .bottomBar)
            .alert(
                pendingBulkAction?.confirmationTitle(count: selectedIDs.count) ?? "",
                isPresented: Binding(
                    get: { pendingBulkAction != nil },
                    set: { if !$0 { pendingBulkAction = nil } }
                ),
                presenting: pendingBulkAction
            ) { action in
                Button("cancelar", role: .cancel) {}
                Button(action.confirmationButtonLabel, role: action.isDestructive ? .destructive : nil) {
                    perform(action)
                }
            } message: { action in
                Text(action.confirmationMessage)
            }
            .alert(
                pendingDiscountBatch?.confirmationTitle ?? "",
                isPresented: Binding(
                    get: { pendingDiscountBatch != nil },
                    set: { if !$0 { pendingDiscountBatch = nil } }
                ),
                presenting: pendingDiscountBatch
            ) { batch in
                Button("cancelar", role: .cancel) {}
                Button(PublishedBulkAction.applyDiscount.confirmationButtonLabel) {
                    applyDiscount(to: batch.items)
                    pendingDiscountBatch = nil
                }
            } message: { batch in
                Text(batch.confirmationMessage)
            }
            // Vale mudar o intervalo no meio da rodada: o laço lê o valor a cada produto.
            .onChange(of: storedSpeed) { _, milliseconds in
                runner.delayBetweenProducts = MegaphoneSpeed(milliseconds: milliseconds).duration
                UserDefaults.standard.set(milliseconds, forKey: speedKey(account.id))
            }
            .onChange(of: storedRounds) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: roundsKey(account.id))
            }
            // Sem o campo de busca na tela durante a rodada (ver o `.background` acima), uma busca
            // que continuasse valendo deixaria a lista filtrada sem nada dizendo por quê. A
            // seleção, ao contrário, mantém a busca de propósito: buscar e depois "selecionar tudo"
            // é o jeito de agir só no que bateu (o termo aparece embaixo do título, ver
            // `AccountDetailView.subtitle`).
            .onChange(of: isRoundOpen) { _, isOpen in
                if isOpen { searchText = "" }
            }
            // Trocar de filtro com itens marcados deixaria parte da seleção "invisível" mas ainda
            // contando pras ações em massa.
            .onChange(of: filter) { _, _ in
                endSelection()
                recomputeSections()
            }
            // `initial: true` cobre tanto a primeira vez que esta view aparece quanto cada troca de
            // conta — sem identidade nova por conta (ver `AccountDetailView.swift`), é o único
            // gatilho que sobrou pra recarregar `storedRounds`/`storedSpeed` e zerar o resto do
            // estado local.
            .onChange(of: account.id, initial: true) { _, newAccountID in
                storedRounds = UserDefaults.standard.object(forKey: roundsKey(newAccountID)) as? Int ?? 1
                storedSpeed = UserDefaults.standard.object(forKey: speedKey(newAccountID)) as? Int
                    ?? MegaphoneSpeed.standard.milliseconds
                searchDebounceTask?.cancel()
                searchDebounceTask = nil
                pendingBulkAction = nil
                pendingDiscountBatch = nil
                recomputeSections()
            }
            // `runner.progressSnapshot`, não `runner.items` direto: `items` muda uma vez por
            // produto megafonado (até 1500+ vezes por rodada) — um `.onChange` nele precisa
            // comparar a lista INTEIRA (`Equatable` sintetizado de `MegaphoneItem`, campo a campo,
            // incluindo strings) a cada mutação de UM item, então o app inteiro passava a gastar
            // O(catálogo) só decidindo se disparava o `onChange`, a cada produto, em cada rodada —
            // confirmado numa amostra de CPU depois de muitas rodadas seguidas (o processo ficava
            // preso em `MegaphoneItem`/`EnjoeiProduct`.`__derived_struct_equals` e retain/release
            // em cima disso). `progressSnapshot` já é o resumo em lote pensado exatamente pra isso
            // (ver seu doc comment) — struct pequena, comparação barata, atualizada a cada
            // `progressSnapshotBatchSize` itens em vez de a cada um.
            .onChange(of: runner.progressSnapshot) { _, _ in recomputeSections() }
            // Debounce: espera a digitação parar por 200ms antes de refiltrar, em vez de refazer o
            // filtro (potencialmente sobre centenas de produtos publicados) a cada tecla.
            .onChange(of: searchText) { _, _ in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    recomputeSections()
                }
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                // "tudo", não "todos": a cápsula de cada seção também seleciona "os N" dela — esta
                // vale pra lista inteira (só as seções abertas, ver `visibleIDs`).
                Button(isAllVisibleSelected ? "desmarcar tudo" : "selecionar tudo") { toggleSelectAllVisible() }
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
            // No iPhone também: o filtro saiu da barra de cima (virou a fileira de cápsulas embaixo
            // das abas, em `AccountDetailView`), e com ele o menu onde o recarregar do iPhone
            // morava — agora cabe um botão à parte.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Mexe nos publicados também — não dá pra trocar a lista com uma rodada em
                    // aberto em cima dela. Checado aqui também porque no Mac o botão nunca fica
                    // desabilitado (ver `ToolbarItemDisabled`).
                    guard !runner.isRunning else { return }
                    account.reloadAllProducts()
                } label: {
                    Label("recarregar produtos", systemImage: "arrow.clockwise")
                }
                .toolbarItemDisabled(runner.isRunning)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("selecionar") {
                    // Ver o recarregar acima — no Mac o botão nunca fica desabilitado.
                    guard !sections.isEmpty else { return }
                    isSelecting = true
                }
                .fixedSize()
                .toolbarItemDisabled(sections.isEmpty)
            }
            // No iPad/Mac a barra parada é a `MegaphoneIdleBar`, flutuando (ver `bottomBar`).
            if !isRoundOpen, isCompact {
                idleBottomBar
            }
        }
    }

    /// "5× · 0,9s", a lupa da busca e "megafonar" — só no iPhone (no iPad/Mac, `MegaphoneIdleBar`).
    ///
    /// O texto desses itens para no `.xLarge`, abaixo do `.xxxLarge` do resto do app (ver
    /// `MBAdminApp`): no tamanho cheio os três não cabem lado a lado no iPhone, e o sistema joga
    /// "megafonar" pra dentro do menu "mais" da barra — escondendo justamente a ação principal.
    @ToolbarContentBuilder
    private var idleBottomBar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            MegaphoneSettingsMenu(rounds: $storedRounds, speedMilliseconds: $storedSpeed, usesShortLabel: isCompact)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        } else {
            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button {
                startMegaphoning()
            } label: {
                // A quantidade de vezes já aparece ao lado, no menu de repetições — sem repetir
                // aqui. `HStack` em vez de `Label`: na barra de baixo o sistema reduz um `Label` só
                // ao ícone, ignorando `.labelStyle(.titleAndIcon)`.
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill")
                    Text("megafonar")
                }
                .fontWeight(.semibold)
                .foregroundStyle(.onTint)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            .prominentGlassButtonStyle()
            .fixedSize()
            // Sem isso, o VoiceOver lê o nome do símbolo junto do texto.
            .accessibilityLabel("megafonar")
        }
    }

    // MARK: - Barra de baixo

    @ViewBuilder
    private var bottomBar: some View {
        if isSelecting {
            SelectionActionBar(actions: availableBulkActions, isEnabled: !selectedIDs.isEmpty) { action in
                pendingBulkAction = action
            }
        } else if isRoundOpen {
            MegaphoneRunPanel(
                runner: runner,
                rounds: $storedRounds,
                speedMilliseconds: $storedSpeed,
                isFollowing: $isFollowing,
                isCompact: isCompact
            )
        } else if !isCompact {
            MegaphoneIdleBar(rounds: $storedRounds, speedMilliseconds: $storedSpeed, onStart: startMegaphoning)
        }
    }

    private func startMegaphoning() {
        runner.delayBetweenProducts = speed.duration
        runner.start(sellerID: account.user.id, rounds: rounds)
    }

    // MARK: - Seleção

    private var visibleIDs: [Int] { sections.visibleIDs(collapsed: collapsedSections) }

    private var isAllVisibleSelected: Bool {
        let ids = visibleIDs
        return !ids.isEmpty && ids.allSatisfy { selectedIDs.contains($0) }
    }

    private func toggleSelectAllVisible() {
        selectedIDs = PublishedProductSections.togglingAll(visibleIDs, in: selectedIDs)
    }

    private func toggleSelection(itemID: Int) {
        if selectedIDs.contains(itemID) {
            selectedIDs.remove(itemID)
        } else {
            selectedIDs.insert(itemID)
        }
    }

    private func endSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private var selectedItems: [MegaphoneItem] {
        (sections.discount + sections.others).filter { selectedIDs.contains($0.id) }
    }

    /// "Aplicar desconto" só com pelo menos um produto que pede desconto na seleção — e só esses
    /// recebem o desconto (os outros não têm preço sugerido pra aplicar).
    private var availableBulkActions: [PublishedBulkAction] {
        let others: [PublishedBulkAction] = [.repost, .inactivate, .delete]
        let hasDiscountCandidate = sections.discount.contains { selectedIDs.contains($0.id) }
        return hasDiscountCandidate ? [.applyDiscount] + others : others
    }

    /// Repostar/inativar/apagar entram na mesma fila de ações usada pelo menu "..." de cada linha
    /// — origem e destino são a própria conta.
    private func perform(_ action: PublishedBulkAction) {
        let items = selectedItems
        switch action {
        case .applyDiscount:
            applyDiscount(to: items)
        case .repost:
            for item in items {
                accountsStore.postQueue.enqueue(product: item.product, source: account, destination: account)
            }
        case .inactivate:
            for item in items {
                accountsStore.postQueue.enqueueInactivate(product: item.product, account: account)
            }
        case .delete:
            for item in items {
                accountsStore.postQueue.enqueueDelete(product: item.product, account: account)
            }
        }
        pendingBulkAction = nil
        endSelection()
    }

    /// Mesma rota da ação em massa "desconto" da seleção e do "aplicar nos N" do cabeçalho de
    /// "pedem desconto": só quem pede desconto tem preço sugerido pra aplicar.
    private func applyDiscount(to items: [MegaphoneItem]) {
        for item in items where item.needsDiscountDecision {
            runner.applyDiscount(for: item.id)
        }
    }

    // MARK: - Lista

    /// Refaz as seções inteiras de uma vez só — chamado só quando `filter`, `runner.items` ou
    /// `searchText` mudam de verdade, não a cada leitura (ver os `@State`/`onChange` acima).
    /// A busca por título consulta o SwiftData (`runner.searchProductIDs(matching:)` — `#Predicate`
    /// + `fetchLimit`, sem `JSONDecoder`), mas só pra saber QUAIS ids batem — os itens em si sempre
    /// vêm de `runner.items` (a lista ao vivo), nunca reconstruídos a partir do que foi persistido:
    /// status/exposição salvos nunca refletem uma megafonagem em andamento (só existe ao vivo aqui),
    /// então buscar aceitando esse "atraso" mostraria status errado de propósito. Ver
    /// `MegaphoneItemRecord`/`MegaphoneRunner.searchProductIDs(matching:)`.
    private func recomputeSections() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingIDs = trimmedSearch.isEmpty ? nil : Set(runner.searchProductIDs(matching: trimmedSearch))
        sections = PublishedProductSections(items: runner.items, filter: filter, matchingIDs: matchingIDs)
    }

    @ViewBuilder
    private var productList: some View {
        // `progressSnapshot.itemsCount`, não `runner.items.isEmpty` direto — ler `items` aqui
        // prenderia esta view (e o resto do `body`) a reavaliar a cada produto megafonado, mesmo
        // `.isEmpty` sendo O(1).
        if runner.progressSnapshot.itemsCount == 0 {
            ContentUnavailableView(
                "nenhum produto na fila",
                systemImage: "shippingbox",
                description: Text("toque em megafonar para buscar os produtos da sua loja.")
            )
            .frame(maxHeight: .infinity)
        } else if sections.isEmpty {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "nenhum produto pede desconto agora",
                    systemImage: "checkmark.circle",
                    description: Text("troque o filtro pra \"todos os anúncios\" pra ver a fila inteira.")
                )
                .frame(maxHeight: .infinity)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // `LazyVStack` em vez de `List`: no idiom otimizado do Mac Catalyst, `List` vira
                    // `NSTableView` por baixo, caro pra reconstruir do zero. `LazyVStack` não passa
                    // por essa ponte e ainda mantém a virtualização (só monta as linhas visíveis) —
                    // importante já que esta view mantém identidade estável entre contas (ver o
                    // comentário no topo de `AccountDetailView.swift`), então os `ForEach` abaixo
                    // é que de fato atualizam item a item ao trocar de conta, em vez de reconstruir
                    // do zero.
                    LazyVStack(spacing: 0) {
                        section(.discount, title: "pedem desconto", titleColor: .statusDecision)
                        section(.others, title: "todos os anúncios")
                    }
                    .padding(.bottom, 8)
                }
                // O da vez (não o último terminado) — é a linha destacada, e a que sobe pro centro.
                .onChange(of: runner.activeItemID) { _, newValue in
                    guard isFollowing, let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ kind: PublishedProductSections.Kind, title: String, titleColor: Color? = nil) -> some View {
        let items = sections.items(in: kind)
        if !items.isEmpty {
            let isCollapsed = collapsedSections.contains(kind)
            let ids = items.map(\.id)
            PublishedSectionHeader(
                title: title,
                count: items.count,
                titleColor: titleColor,
                isCollapsed: isCollapsed,
                horizontalPadding: isCompact ? 16 : 24,
                // Vale mesmo com a seção recolhida — o cabeçalho diz de quantos se trata, e nada
                // entra na fila sem o alerta de confirmação com a contagem.
                selectionState: isSelecting ? SectionSelectionState(sectionIDs: ids, selectedIDs: selectedIDs) : nil,
                onSelectAll: { selectedIDs = PublishedProductSections.togglingAll(ids, in: selectedIDs) }
            ) {
                withAnimation(.snappy) {
                    if isCollapsed {
                        collapsedSections.remove(kind)
                    } else {
                        collapsedSections.insert(kind)
                    }
                }
            } trailingAction: {
                if kind == .discount {
                    applyDiscountButton(for: items)
                }
            }
            if !isCollapsed {
                rows(items)
            }
        }
    }

    /// "aplicar nos N" — o uso mais comum da aba (aplicar o desconto sugerido em todos que pedem) a
    /// um toque, sem passar pela seleção; nada muda antes do alerta com a lista de preços. Some
    /// quando nenhum da seção ainda espera a decisão (ver `PendingDiscountBatch`). Só aparece fora
    /// da seleção — lá o cabeçalho troca isso pela cápsula de selecionar.
    @ViewBuilder
    private func applyDiscountButton(for items: [MegaphoneItem]) -> some View {
        let batch = PendingDiscountBatch(section: items) { id in
            runner.deleteStatuses[id] == .succeeded || runner.inactivateStatuses[id] == .succeeded
        }
        if !batch.isEmpty {
            Button {
                pendingDiscountBatch = batch
            } label: {
                Label(batch.buttonLabel, systemImage: "tag.fill")
                    .foregroundStyle(.onTint)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.statusDecision)
            // Mesmo limite de tamanho da cápsula de selecionar a seção (ver
            // `PublishedSectionHeader.selectAllCapsule`) — no iPhone, título e botão não cabiam lado a
            // lado no `.xxxLarge` do app.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .fixedSize()
            .accessibilityLabel(batch.accessibilityLabel)
        }
    }

    private func rows(_ items: [MegaphoneItem]) -> some View {
        // A fase só muda nas transições (começar, pausar, terminar) — barato de ler aqui, ao
        // contrário de `runner.items`.
        let isRoundActive = runner.phase.isActive
        // Muda a cada produto, como `.onChange(of: runner.activeItemID)` lá em cima já faz esta
        // view reavaliar — só as duas linhas envolvidas (a que saiu e a que entrou) mudam no `==`
        // de `MegaphoneRowView`.
        let activeID = runner.activeItemID
        let lastID = items.last?.id
        return ForEach(items) { item in
            MegaphoneRowView(
                item: item,
                runner: runner,
                account: account,
                isSelecting: isSelecting,
                isSelected: selectedIDs.contains(item.id),
                isRoundActive: isRoundActive,
                isActive: item.id == activeID,
                isCompact: isCompact,
                onToggleSelection: { toggleSelection(itemID: item.id) }
            )
            // Ver `MegaphoneRowView.==` — sem isso, o SwiftUI usa a comparação automática de
            // `item: MegaphoneItem` (cara) pra decidir se recria a linha; com isso, usa a
            // comparação enxuta da própria view.
            .equatable()
            if item.id != lastID {
                // Começa onde começa o texto: margem + foto + espaçamento (+ o círculo de seleção).
                Divider()
                    .padding(.leading, (isCompact ? 16 : 24) + 64 + 12 + (isSelecting ? 36 : 0))
            }
        }
    }
}
