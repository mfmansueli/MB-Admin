import SwiftUI

/// Tela principal: mostra a lista de contas logadas ou o convite para entrar.
struct ContentView: View {
    @Environment(AccountsStore.self) private var accountsStore

    var body: some View {
        Group {
            if accountsStore.isRestoring {
                ProgressView("conferindo suas sessões…")
            } else {
                AccountsListView()
            }
        }
        .animation(.default, value: accountsStore.isRestoring)
        // As WebViews de bastidores ficam sempre aqui, num ponto no canto: é delas que saem as
        // chamadas autenticadas de cada conta. Uma por conta, todas montadas ao mesmo tempo, pra
        // várias contas conseguirem megafonar em paralelo mesmo fora da tela de detalhe — e nenhuma
        // muda de lugar na hierarquia depois de montada, trocar uma WebView de tela no meio de um
        // toque derruba o app.
        .background(alignment: .bottomLeading) {
            ForEach(accountsStore.accounts) { account in
                if let webView = account.webView {
                    AccountWebSessionHost(webView: webView)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .task {
            guard accountsStore.isRestoring else { return }
            await accountsStore.restoreAccounts()
        }
    }
}

#Preview {
    ContentView()
        .environment(AccountsStore())
}
