import Foundation
import Observation

/// Estado global do app: quem está logado, e as transições de login/logout.
@MainActor
@Observable
final class AppSession {
    private(set) var state: SessionState = .checking
    /// Erro digno de aparecer na tela principal (problema de verdade, não "ninguém logado").
    private(set) var errorMessage: String?
    /// Recado mostrado dentro da tela de login quando a conferência não encontra ninguém logado.
    private(set) var loginFeedback: String?

    let client: EnjoeiClientProtocol
    private let sessionClearer: EnjoeiSessionClearing

    init(client: EnjoeiClientProtocol? = nil, sessionClearer: EnjoeiSessionClearing? = nil) {
        self.client = client ?? WebViewEnjoeiClient()
        self.sessionClearer = sessionClearer ?? EnjoeiWebSession.shared
    }

    /// Abertura do app: a WebView guarda os cookies em disco, então basta perguntar à página quem
    /// está logado.
    func restoreSession() async {
        state = .checking
        await loadCurrentUser(reloadingPage: false)
    }

    /// Conferência da tela de login, disparada a cada página carregada e pelo botão "já entrei".
    ///
    /// - Parameter triggeredByUser: só o toque no botão merece recado na tela; a conferência
    ///   automática roda a cada página e ficaria barulhenta.
    @discardableResult
    func checkLoginFromWebView(triggeredByUser: Bool = false) async -> Bool {
        // Recarrega: a página de bastidores é anterior ao login e ainda se acha deslogada.
        let failure = await loadCurrentUser(reloadingPage: true)
        guard state.isLoggedIn else {
            if triggeredByUser { loginFeedback = Self.loginFeedback(for: failure) }
            return false
        }
        loginFeedback = nil
        isPresentingLogin = false
        return true
    }

    var isPresentingLogin = false

    func startLogin() {
        errorMessage = nil
        loginFeedback = nil
        isPresentingLogin = true
    }

    func logout() async {
        await sessionClearer.clearSession()
        errorMessage = nil
        loginFeedback = nil
        state = .loggedOut
    }

    /// Recado padrão quando a conferência não achou sessão — o login ainda não terminou.
    static let notLoggedInYetFeedback =
        "ainda não te encontrei logado. termine o login no enjoei e toque de novo em já entrei."

    /// Carrega o usuário atual. Devolve o erro que impediu, quando houver.
    @discardableResult
    private func loadCurrentUser(reloadingPage: Bool) async -> Error? {
        do {
            state = .loggedIn(try await client.currentUser(reloadingPage: reloadingPage))
            errorMessage = nil
            return nil
        } catch {
            state = .loggedOut
            // "ninguém logado" não é defeito: não vira alarme na tela principal.
            errorMessage = Self.isGuestFailure(error) ? nil : error.localizedDescription
            return error
        }
    }

    private static func isGuestFailure(_ error: Error) -> Bool {
        switch error as? EnjoeiError {
        case .notAuthenticated, .notIdentified: true
        default: false
        }
    }

    private static func loginFeedback(for failure: Error?) -> String {
        guard let failure else { return notLoggedInYetFeedback }
        guard isGuestFailure(failure) else { return failure.localizedDescription }
        // Nos casos de "não identifiquei", o detalhe técnico ajuda a entender o que a página disse.
        if case .notIdentified(let detail) = failure as? EnjoeiError, !detail.isEmpty {
            return "\(notLoggedInYetFeedback)\n(\(detail))"
        }
        return notLoggedInYetFeedback
    }
}
