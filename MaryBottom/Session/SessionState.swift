import Foundation

/// Estado de autenticação mostrado na tela principal.
nonisolated enum SessionState: Equatable {
    /// Ainda conferindo os cookies guardados, logo na abertura do app.
    case checking
    case loggedOut
    case loggedIn(EnjoeiUser)

    var user: EnjoeiUser? {
        if case .loggedIn(let user) = self { return user }
        return nil
    }

    var isLoggedIn: Bool { user != nil }
}
