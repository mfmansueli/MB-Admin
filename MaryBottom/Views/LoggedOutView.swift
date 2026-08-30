import SwiftUI

/// Estado deslogado: explica o que o app faz e abre o login.
struct LoggedOutView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("megafone em série")
                    .font(.largeTitle.bold())
                Text("entre com sua conta do enjoei para megafonar todos os produtos da sua loja de uma vez.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                session.startLogin()
            } label: {
                Text("entrar no enjoei")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}

#Preview {
    LoggedOutView()
        .environment(AppSession())
}
