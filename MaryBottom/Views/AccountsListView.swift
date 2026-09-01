import SwiftUI

/// Raiz do estado logado: lista as contas do Enjoei ao lado (ou empilhada, no iPhone) do detalhe da
/// conta selecionada, e o botão pra adicionar mais uma na toolbar.
struct AccountsListView: View {
    @Environment(AccountsStore.self) private var accountsStore
    @State private var editMode: EditMode = .inactive
    @State private var selectedAccountID: EnjoeiAccountID?
    @State private var isPresentingComparison = false
    @State private var isShowingQueue = false

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
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .topBarTrailing) {
                    // A fila roda em segundo plano mesmo com a tela de comparação fechada — esse
                    // botão é o único jeito de conferir o andamento dela sem reabrir aquela tela.
                    Button {
                        isShowingQueue = true
                    } label: {
                        if accountsStore.postQueue.isRunning {
                            PublishingQueueIcon()
                        } else {
                            Label("fila de publicação", systemImage: "list.bullet.rectangle")
                        }
                    }
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
                AccountDetailView(account: account)
            } else {
                ContentUnavailableView("selecione uma conta", systemImage: "person.crop.circle")
            }
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
        .fullScreenCover(isPresented: $isPresentingComparison) {
            AccountComparisonView(accounts: accountsStore.accounts)
                .environment(accountsStore)
        }
        .sheet(isPresented: $isShowingQueue) {
            PostQueueView(postQueue: accountsStore.postQueue, poster: accountsStore.poster)
        }
    }

    /// Conta com sessão vencida resolve ali mesmo (reabrindo o login) em vez de selecionar e mostrar
    /// o detalhe — não tem o que mostrar de megafone enquanto ela não está autenticada.
    @ViewBuilder
    private func row(for account: AccountSession) -> some View {
        if account.status == .sessionExpired {
            Button {
                accountsStore.retryLogin(for: account.id)
            } label: {
                AccountRowView(account: account)
            }
            .buttonStyle(.plain)
        } else {
            AccountRowView(account: account)
        }
    }
}
