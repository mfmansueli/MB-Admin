import SwiftUI

/// Conteúdo do sheet que fica aberto do momento em que o usuário confirma o repost até o resultado
/// sair — sem isso, entre confirmar e o resultado final o usuário não tinha nenhum retorno visível.
struct RepostStatusSheet: View {
    let status: MegaphoneStatus
    /// Link do anúncio NOVO — `nil` quando a resposta da criação não trouxe como identificar ele.
    /// Sem link certo do novo produto, não mostra "visualizar": o usuário pediu explicitamente
    /// pra não cair no produto antigo como se fosse o resultado do repost.
    let productURL: URL?
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            switch status {
            case .pending, .megaphoning:
                ProgressView()
                    .controlSize(.large)
                Text("repostando o produto…")
                    .font(.headline)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.statusSuccess)
                Text("produto repostado com sucesso.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("ok", action: onDismiss)
                        .buttonStyle(.bordered)
                    if let productURL {
                        Button {
                            openURL(productURL)
                            onDismiss()
                        } label: {
                            // `.onTint`: o estilo proeminente pinta o texto de branco, que some em
                            // cima da ação principal no modo escuro (`#F2F2F7`).
                            Text("visualizar").foregroundStyle(.onTint)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.statusFailure)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button(action: onDismiss) {
                    Text("ok").foregroundStyle(.onTint)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(220)])
        // Enquanto ainda está rodando, não deixa fechar por engano e perder de vista o andamento.
        .interactiveDismissDisabled(status == .pending || status == .megaphoning)
    }
}

#Preview {
    RepostStatusSheet(
        status: .megaphoning,
        productURL: URL(string: "https://www.enjoei.com.br/p/exemplo")!,
        onDismiss: {}
    )
}
