import SwiftUI

/// Tela modal com o login do Enjoei. Fecha sozinha assim que a sessão aparece.
struct LoginSheetView: View {
    let accountID: EnjoeiAccountID

    @Environment(AccountsStore.self) private var accountsStore
    @Environment(\.dismiss) private var dismiss
    @State private var isCheckingSession = false
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            LoginWebView(dataStoreIdentifier: accountID) { _ in
                checkSession(triggeredByUser: false)
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                if let feedback {
                    Text(feedback)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(.yellow.opacity(0.2))
                }
            }
            .navigationTitle("entrar no enjoei")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("fechar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCheckingSession {
                        ProgressView()
                    } else {
                        Button("já entrei") { checkSession(triggeredByUser: true) }
                    }
                }
            }
        }
    }

    private func checkSession(triggeredByUser: Bool) {
        guard !isCheckingSession else { return }
        isCheckingSession = true
        Task {
            let outcome = await accountsStore.checkLoginFromWebView(accountID: accountID)
            switch outcome {
            case .loggedIn:
                feedback = nil
                dismiss()
            case .pending(let message):
                // Só o toque no botão merece recado na tela; a conferência automática roda a cada
                // página e ficaria barulhenta.
                if triggeredByUser { feedback = message }
            }
            isCheckingSession = false
        }
    }
}
