import SwiftUI

/// Raiz do estado logado: lista as contas do Enjoei ao lado (ou empilhada, no iPhone) do detalhe da
/// conta selecionada. As contas com uma rodada em aberto sobem pra "rodando agora", separadas das
/// "paradas" — o que está acontecendo agora fica no topo, sem precisar entrar em cada uma.
struct AccountsListView: View {
    @Environment(AccountsStore.self) private var accountsStore
    /// Lido aqui, fora do `NavigationSplitView` — dentro das colunas o valor nem sempre reflete a
    /// janela inteira, e é a janela que decide entre o layout de iPhone e o de barra lateral.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive
    @State private var selectedAccountID: EnjoeiAccountID? = Self.initialSelectedAccountID
    @State private var isPresentingComparison = false
    @State private var isShowingQueue = false
    /// Tamanho atual da janela no Mac Catalyst — só serve pra dimensionar o `.sheet` de comparação
    /// proporcionalmente (ver uso abaixo); em iPhone/iPad não é lido em lugar nenhum.
    @State private var windowSize: CGSize = .zero

    private var isCompact: Bool { horizontalSizeClass == .compact }

    /// Sempre nenhuma fora do modo de demonstração (ver `DemoMode.initialSelectedAccountID`).
    private static var initialSelectedAccountID: EnjoeiAccountID? {
        #if DEBUG
        DemoMode.initialSelectedAccountID
        #else
        nil
        #endif
    }

    var body: some View {
        @Bindable var accountsStore = accountsStore

        NavigationSplitView {
            Group {
                if accountsStore.accounts.isEmpty {
                    LoggedOutView()
                } else {
                    accountsList
                }
            }
            .navigationTitle("contas")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
        } detail: {
            if let account = accountsStore.accounts.first(where: { $0.id == selectedAccountID }) {
                // Sem `.id` de propósito — ver o comentário no topo de `AccountDetailView.swift`
                // sobre como ela mesma lida com trocar de conta sem vazar estado.
                AccountDetailView(account: account)
            } else {
                ContentUnavailableView("selecione uma conta", systemImage: "person.crop.circle")
            }
        }
        // Mede a janela inteira (o `NavigationSplitView` ocupa ela toda) pra poder dimensionar o
        // `.sheet` de comparação como uma fração desse tamanho, em vez de um valor fixo — arrastar
        // a borda da janela no Mac atualiza `windowSize`, e como o `.sheet` já presente lê esse
        // valor de novo a cada recomposição, ele acompanha o redimensionamento.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            windowSize = newSize
        }
        // Espelha a seleção pro `AccountsStore` — só pra `releaseIdleAccountsMemory()` saber qual
        // conta não liberar memória (a que o usuário está olhando agora). A seleção em si continua
        // vivendo aqui, sem mudar de comportamento nenhum.
        .onChange(of: selectedAccountID, initial: true) { _, newValue in
            accountsStore.selectedAccountID = newValue
        }
        .sheet(isPresented: $accountsStore.isPresentingLogin) {
            if let accountID = accountsStore.pendingLoginAccountID {
                // No Mac Catalyst, o conteúdo de `.sheet`/`.fullScreenCover` às vezes não herda o
                // `.environment(accountsStore)` injetado lá em cima em `MBAdminApp` — crasha com
                // "No Observable object of type AccountsStore found" ao ler `@Environment
                // (AccountsStore.self)` dentro da view apresentada. Reinjetar aqui garante que
                // sempre está disponível, independente desse bug de propagação.
                LoginSheetView(accountID: accountID)
                    .environment(accountsStore)
            }
        }
        // No Mac Catalyst, `.fullScreenCover` (que não tem equivalente real numa janela de Mac)
        // já apareceu com o layout todo quebrado em versões mais antigas — como se o conteúdo
        // nunca fosse fixado ao tamanho da janela. `.sheet` já é usado em todo o resto do app sem
        // esse problema, então cobre o mesmo caso ali; no iPhone/iPad, `.fullScreenCover` continua
        // valendo, sem mudar o comportamento de quem já usa assim.
        #if targetEnvironment(macCatalyst)
        .sheet(isPresented: $isPresentingComparison) {
            AccountComparisonView(accounts: accountsStore.accounts)
                .environment(accountsStore)
                // Sem frame explícito, o Mac Catalyst dimensiona o `.sheet` pelo tamanho
                // intrínseco do conteúdo — como a tela começa vazia (nenhuma conta comparada
                // ainda), o sheet abre pequeno e centralizado em vez de aproveitar a janela. Usar
                // `idealWidth`/`idealHeight` (em vez de um tamanho fixo) proporcionais a
                // `windowSize` faz o sheet crescer junto quando a janela é redimensionada; os
                // mínimos evitam um sheet minúsculo antes de `windowSize` ser medido (`.zero`) ou
                // com a janela muito pequena.
                .frame(
                    minWidth: 900,
                    idealWidth: max(windowSize.width * 0.9, 900),
                    minHeight: 700,
                    idealHeight: max(windowSize.height * 0.9, 700)
                )
        }
        #else
        .fullScreenCover(isPresented: $isPresentingComparison) {
            AccountComparisonView(accounts: accountsStore.accounts)
                .environment(accountsStore)
        }
        #endif
        .macCatalystSizedSheet(isPresented: $isShowingQueue) {
            PostQueueView(postQueue: accountsStore.postQueue, poster: accountsStore.poster)
        }
    }

    // `runner.phase`, não `runner.progressSnapshot.phase`: o snapshot inteiro é republicado a cada
    // lote de produtos megafonados, e ler ele aqui faria a lista toda reavaliar nesse ritmo — a
    // fase em si só muda nas transições (começar, pausar, terminar).
    private var runningAccounts: [AccountSession] {
        accountsStore.accounts.filter { $0.runner.phase.isActive }
    }

    private var stoppedAccounts: [AccountSession] {
        accountsStore.accounts.filter { !$0.runner.phase.isActive }
    }

    /// Cartões agrupados no iPhone, barra lateral (destaque da seleção na cor de ação principal)
    /// no iPad/Mac — os dois ramos só trocam numa mudança de size class, rara o bastante pra
    /// reconstruir a lista não pesar.
    @ViewBuilder
    private var accountsList: some View {
        if isCompact {
            accountsListContent.listStyle(.insetGrouped)
        } else {
            accountsListContent
                .listStyle(.sidebar)
                // O destaque da conta selecionada sai da cor de ação principal — que no escuro é
                // quase branca (`#F2F2F7`), e o sistema escreve o texto da row selecionada em
                // branco por cima, ilegível. `SidebarSelection` é a mesma ação principal no claro e
                // um cinza médio no escuro, onde o texto branco continua lendo.
                .tint(.sidebarSelection)
        }
    }

    private var accountsListContent: some View {
        let running = runningAccounts
        let stopped = stoppedAccounts
        return List(selection: $selectedAccountID) {
            if !running.isEmpty {
                Section {
                    rows(for: running)
                } header: {
                    sectionHeader("rodando agora")
                }
            }
            if !stopped.isEmpty {
                Section {
                    rows(for: stopped)
                } header: {
                    // Sozinha, a seção dispensa título — "paradas" só ajuda a separar das que
                    // estão rodando.
                    if !running.isEmpty {
                        sectionHeader("paradas")
                    }
                }
            }
        }
        .animation(.default, value: running.map(\.id))
        // O botão "editar" na toolbar controla esse `editMode` direto (em vez de ler o
        // `@Environment(\.editMode)`, que fica `nil` sem alguém injetando ele) — sem isso, a List
        // nunca entra no modo de edição de verdade e o controle de remover por linha não aparece.
        .environment(\.editMode, $editMode)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.supportingText)
            .textCase(nil)
    }

    private func rows(for accounts: [AccountSession]) -> some View {
        ForEach(accounts) { account in
            row(for: account)
                .swipeActions(edge: .trailing) {
                    Button("sair", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        Task { await accountsStore.logout(accountID: account.id) }
                    }
                    .tint(.statusFailure)
                }
                // O swipe não tem como fazer no Mac Catalyst com mouse (só toque ou trackpad
                // reconhecem o gesto) — o clique direito cobre o mesmo caminho lá, sem tirar o
                // swipe de quem usa toque.
                .contextMenu {
                    Button("sair", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        Task { await accountsStore.logout(accountID: account.id) }
                    }
                }
        }
        // `.onDelete` habilita o modo de edição (botão "editar" na toolbar) a mostrar o controle de
        // remoção por linha — no Mac Catalyst é o único caminho visual pra sair de uma conta, já
        // que nem swipe nem clique direito são óbvios ali.
        .onDelete { offsets in
            for index in offsets {
                let account = accounts[index]
                Task { await accountsStore.logout(accountID: account.id) }
            }
        }
    }

    /// Conta com sessão vencida ou não conferida ainda resolve ali mesmo (reabrindo o login, ou
    /// tentando a checagem de novo) em vez de selecionar e mostrar o detalhe — não tem o que
    /// mostrar de megafone enquanto não se sabe se ela está autenticada.
    @ViewBuilder
    private func row(for account: AccountSession) -> some View {
        switch account.status {
        case .sessionExpired:
            Button {
                accountsStore.retryLogin(for: account.id)
            } label: {
                AccountRowView(account: account)
            }
            .buttonStyle(.plain)
        case .checkFailed:
            Button {
                accountsStore.retryCheckingSession(for: account.id)
            } label: {
                AccountRowView(account: account)
            }
            .buttonStyle(.plain)
        case .active:
            AccountRowView(account: account)
        }
    }

    /// iPhone: "editar" no canto de cima, "comparar lojas" sozinho embaixo. Barra lateral
    /// (iPad/Mac): os dois embaixo, como no rodapé de uma barra lateral — em cima fica só o que
    /// adiciona conta e a fila.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isCompact {
            ToolbarItem(placement: .topBarLeading) {
                editButton
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                accountsStore.beginAddingAccount()
            } label: {
                Label("adicionar conta", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            queueButton
        }
        if isCompact {
            bottomBarSpacer
            ToolbarItem(placement: .bottomBar) {
                compareButton(title: "comparar lojas")
            }
            bottomBarSpacer
        } else {
            ToolbarItem(placement: .bottomBar) {
                editButton
            }
            bottomBarSpacer
            ToolbarItem(placement: .bottomBar) {
                compareButton(title: "comparar")
            }
        }
    }

    @ToolbarContentBuilder
    private var bottomBarSpacer: some ToolbarContent {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        } else {
            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }
        }
    }

    /// `EditButton()` fica com o texto preto sobre fundo preto na toolbar de baixo no Mac Catalyst
    /// (bug de contraste da view do sistema) — um botão próprio evita o problema. `.fixedSize()`
    /// evita o texto truncar ("ed...") — sem isso, o botão no Mac (idiom otimizado) encolhe pro
    /// tamanho de uma "pill" fixa em vez de acompanhar o texto.
    private var editButton: some View {
        Button(editMode.isEditing ? "concluir" : "editar") {
            withAnimation {
                editMode = editMode.isEditing ? .inactive : .active
            }
        }
        .fixedSize()
        .disabled(accountsStore.accounts.isEmpty)
    }

    /// A fila roda em segundo plano mesmo com a tela de comparação fechada — esse botão é o único
    /// jeito de conferir o andamento dela sem reabrir aquela tela. O selo conta o que ainda está
    /// esperando a vez.
    private var queueButton: some View {
        let pendingCount = accountsStore.postQueue.items.count
        return Button {
            isShowingQueue = true
        } label: {
            PublishingQueueIcon(isAnimating: accountsStore.postQueue.isRunning)
                // Tamanho fixo, igual ao de antes do redesign — sem isso, o bezel padrão de toolbar
                // deixa o ícone (desenhado à mão, com um tamanho próprio) espremido/distorcido em
                // versões mais antigas do Mac Catalyst.
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    if pendingCount > 0 {
                        Text(pendingCount.formatted())
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.statusFailure, in: .capsule)
                            .offset(x: 6, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pendingCount > 0 ? "fila de ações, \(pendingCount) itens" : "fila de ações")
    }

    /// No iPad, um `Label` nessa toolbar (dentro da coluna lateral do `NavigationSplitView`) vira
    /// ícone-only automaticamente, ignorando `.labelStyle(.titleAndIcon)` — uma `HStack` manual de
    /// ícone+texto escapa desse colapso. `.fixedSize()` faz o mesmo papel no Mac (idiom otimizado),
    /// onde sem ele o texto "comparar" some por completo, sobrando só o ícone.
    private func compareButton(title: String) -> some View {
        Button {
            isPresentingComparison = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle")
                Text(title)
            }
            .fontWeight(.semibold)
        }
        .fixedSize()
        .disabled(accountsStore.accounts.count < 2)
    }
}
