import SwiftUI

/// Tela principal: mostra a loja de quem está logado ou o convite para entrar.
struct ContentView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var session = session

        Group {
            switch session.state {
            case .checking:
                ProgressView("conferindo sua sessão…")
            case .loggedOut:
                LoggedOutView()
            case .loggedIn(let user):
                LoggedInView(user: user, client: session.client)
            }
        }
        .animation(.default, value: session.state)
        // A WebView de bastidores fica sempre aqui, num ponto no canto: é dela que saem as chamadas
        // autenticadas. Ela nunca muda de lugar na hierarquia — trocar uma WebView de tela no meio
        // de um toque derruba o app.
        .background(alignment: .bottomLeading) {
            SessionWebViewHost()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $session.isPresentingLogin) {
            LoginSheetView()
        }
        .task {
            guard case .checking = session.state else { return }
            await session.restoreSession()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSession())
}
