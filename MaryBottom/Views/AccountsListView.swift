import SwiftUI

/// Raiz do estado logado: lista as contas do Enjoei, com a primeira já mostrando os detalhes dela,
/// e o botão para adicionar mais uma.
struct AccountsListView: View {
    @Environment(AccountsStore.self) private var accountsStore

    var body: some View {
        @Bindable var accountsStore = accountsStore

        NavigationStack {
            Group {
                if accountsStore.accounts.isEmpty {
                    LoggedOutView()
                } else {
                    List {
                        ForEach(accountsStore.accounts) { account in
                            row(for: account)
                                .swipeActions(edge: .trailing) {
                                    Button("sair", role: .destructive) {
                                        Task { await accountsStore.logout(accountID: account.id) }
                                    }
                                }
                        }

                        Button {
                            accountsStore.beginAddingAccount()
                        } label: {
                            Label("adicionar usuário", systemImage: "plus.circle")
                        }
                    }
                    .listStyle(.plain)
                    .navigationDestination(for: EnjoeiAccountID.self) { id in
                        if let account = accountsStore.accounts.first(where: { $0.id == id }) {
                            AccountDetailView(account: account)
                        }
                    }
                }
            }
            .navigationTitle("suas contas")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $accountsStore.isPresentingLogin) {
            if let accountID = accountsStore.pendingLoginAccountID {
                LoginSheetView(accountID: accountID)
            }
        }
    }

    /// Conta com sessão vencida resolve ali mesmo (reabrindo o login) em vez de empurrar pro
    /// detalhe — não tem o que mostrar de megafone enquanto ela não está autenticada.
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
            NavigationLink(value: account.id) {
                AccountRowView(account: account)
            }
        }
    }
}
