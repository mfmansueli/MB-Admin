import SwiftUI

/// Raiz do estado logado: lista as contas do Enjoei ao lado (ou empilhada, no iPhone) do detalhe da
/// conta selecionada, e o botão pra adicionar mais uma na toolbar.
struct AccountsListView: View {
    @Environment(AccountsStore.self) private var accountsStore
    @State private var selectedAccountID: EnjoeiAccountID?

    var body: some View {
        @Bindable var accountsStore = accountsStore

        NavigationSplitView {
            Group {
                if accountsStore.accounts.isEmpty {
                    LoggedOutView()
                } else {
                    List(accountsStore.accounts, selection: $selectedAccountID) { account in
                        row(for: account)
                            .swipeActions(edge: .trailing) {
                                Button("sair", role: .destructive) {
                                    Task { await accountsStore.logout(accountID: account.id) }
                                }
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("suas contas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        accountsStore.beginAddingAccount()
                    } label: {
                        Label("adicionar usuário", systemImage: "plus.circle")
                    }
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
                LoginSheetView(accountID: accountID)
            }
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
