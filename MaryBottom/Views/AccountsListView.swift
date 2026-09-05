import SwiftUI

/// Raiz do estado logado: lista as contas do Enjoei ao lado (ou empilhada, no iPhone) do detalhe da
/// conta selecionada, e o botão pra adicionar mais uma na toolbar.
struct AccountsListView: View {
    @Environment(AccountsStore.self) private var accountsStore
    @State private var editMode: EditMode = .inactive
    @State private var selectedAccountID: EnjoeiAccountID?
    @State private var isPresentingComparison = false
    @State private var isShowingQueue = false
    /// Tamanho atual da janela no Mac Catalyst — só serve pra dimensionar o `.sheet` de comparação
    /// proporcionalmente (ver uso abaixo); em iPhone/iPad não é lido em lugar nenhum.
    @State private var windowSize: CGSize = .zero

    var body: some View {
        @Bindable var accountsStore = accountsStore

        NavigationSplitView {
            Group {
                if accountsStore.accounts.isEmpty {
                    LoggedOutView()
                } else {
                    List(selection: $selectedAccountID) {
                        ForEach(accountsStore.accounts) { account in
                            row(for: account)
                                .swipeActions(edge: .trailing) {
                                    Button("sair", role: .destructive) {
                                        Task { await accountsStore.logout(accountID: account.id) }
                                    }
                                }
                                // O swipe não tem como fazer no Mac Catalyst com mouse (só toque ou
                                // trackpad reconhecem o gesto) — o clique direito cobre o mesmo
                                // caminho lá, sem tirar o swipe de quem usa toque.
                                .contextMenu {
                                    Button("sair", role: .destructive) {
                                        Task { await accountsStore.logout(accountID: account.id) }
                                    }
                                }
                        }
                        // `.onDelete` habilita o modo de edição (botão "editar" na toolbar) a
                        // mostrar o controle de remoção por linha — no Mac Catalyst é o único
                        // caminho visual pra sair de uma conta, já que nem swipe nem clique direito
                        // são óbvios ali.
                        .onDelete { offsets in
                            for index in offsets {
                                let account = accountsStore.accounts[index]
                                Task { await accountsStore.logout(accountID: account.id) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    // O botão "editar" na toolbar controla esse `editMode` direto (em vez de ler o
                    // `@Environment(\.editMode)`, que fica `nil` sem alguém injetando ele) — sem
                    // isso, a List nunca entra no modo de edição de verdade e o controle de remover
                    // por linha não aparece.
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle("contas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        accountsStore.beginAddingAccount()
                    } label: {
                        Label("adicionar usuário", systemImage: "plus.circle")
                    }
                }
                // Sem isso, o "liquid glass" (iOS 26) funde os dois botões trailing numa cápsula só.
                // Versões anteriores não têm liquid glass, então não precisam do spacer.
                if #available(iOS 26.0, macCatalyst 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // A fila roda em segundo plano mesmo com a tela de comparação fechada — esse
                    // botão é o único jeito de conferir o andamento dela sem reabrir aquela tela.
                    //
                    // Círculo com tamanho fixo, igual ao botão "recarregar produtos" — sem isso, o
                    // bezel padrão de toolbar deixa o ícone (e o `PublishingQueueIcon`, desenhado
                    // à mão com um tamanho próprio) espremido/distorcido em versões mais antigas do
                    // Mac Catalyst.
                    Button {
                        isShowingQueue = true
                    } label: {
                        Group {
                            if accountsStore.postQueue.isRunning {
                                PublishingQueueIcon()
                            } else {
                                Label("fila de ações", systemImage: "list.bullet.rectangle")
                                    .labelStyle(.iconOnly)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(.quaternary, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .bottomBar) {
                    // `EditButton()` fica com o texto preto sobre fundo preto nessa toolbar no Mac
                    // Catalyst (bug de contraste da view do sistema) — um botão próprio evita o
                    // problema. `.fixedSize()` evita o texto truncar ("ed...") — sem isso, o botão
                    // no Mac (idiom otimizado) encolhe pro tamanho de uma "pill" fixa em vez de
                    // acompanhar o texto.
                    Button(editMode.isEditing ? "concluir" : "editar") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .fixedSize()
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isPresentingComparison = true
                    } label: {
                        // No iPad, um `Label` nessa toolbar (dentro da coluna lateral do
                        // `NavigationSplitView`) vira ícone-only automaticamente, ignorando
                        // `.labelStyle(.titleAndIcon)` — uma `HStack` manual de ícone+texto escapa
                        // desse colapso. `.fixedSize()` faz o mesmo papel no Mac (idiom otimizado),
                        // onde sem ele o texto "comparar" some por completo, sobrando só o ícone.
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.on.rectangle")
                            Text("comparar")
                        }
                    }
                    .fixedSize()
                    .disabled(accountsStore.accounts.count < 2)
                }
            }
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
                // `.environment(accountsStore)` injetado lá em cima em `MaryBottomApp` — crasha com
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
}
