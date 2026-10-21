import SwiftUI

/// Estado deslogado: explica o que o app faz e abre o login.
struct LoggedOutView: View {
    @Environment(AccountsStore.self) private var accountsStore

    var body: some View {
        VStack(spacing: 24) {
            // A cor da marca só aparece de enfeite — aqui, no ícone da tela de boas-vindas.
            Image(systemName: "megaphone.fill")
                .font(.system(size: 64))
                .foregroundStyle(.brandCoral)

            VStack(spacing: 8) {
                Text("megafone em série")
                    .font(.largeTitle.bold())
                Text("entre com sua conta do enjoei para megafonar todos os produtos da sua loja de uma vez.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                accountsStore.beginAddingAccount()
            } label: {
                // `.onTint`: o estilo proeminente pinta o texto de branco, que some em cima da ação
                // principal no modo escuro (`#F2F2F7`).
                Text("entrar no enjoei")
                    .foregroundStyle(.onTint)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}

#Preview {
    LoggedOutView()
        .environment(AccountsStore())
}
