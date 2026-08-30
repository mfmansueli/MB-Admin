import SwiftUI

/// Conteúdo do sheet que fica aberto do momento em que o usuário confirma apagar até o resultado
/// sair — mesmo raciocínio do `RepostStatusSheet`, sem o botão de visualizar (não tem o que ver
/// depois de apagado).
struct DeleteStatusSheet: View {
    let status: MegaphoneStatus
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch status {
            case .pending, .megaphoning:
                ProgressView()
                    .controlSize(.large)
                Text("apagando o produto…")
                    .font(.headline)
            case .succeeded:
                Image(systemName: "trash.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("produto apagado.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("ok", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("ok", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(220)])
        .interactiveDismissDisabled(status == .pending || status == .megaphoning)
    }
}

#Preview {
    DeleteStatusSheet(status: .megaphoning, onDismiss: {})
}
