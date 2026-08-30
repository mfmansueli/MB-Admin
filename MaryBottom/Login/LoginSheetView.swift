import SwiftUI

/// Tela modal com o login do Enjoei. Fecha sozinha assim que a sessão aparece.
struct LoginSheetView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var isCheckingSession = false

    var body: some View {
        NavigationStack {
            LoginWebView { _ in
                checkSession(triggeredByUser: false)
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                if let feedback = session.loginFeedback {
                    Text(feedback)
                        .font(.footnote)
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
            await session.checkLoginFromWebView(triggeredByUser: triggeredByUser)
            isCheckingSession = false
        }
    }
}
