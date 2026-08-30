import Foundation
import Observation

/// Estado global do app: quais contas do Enjoei estão logadas, e as transições de login/logout de
/// cada uma. Substitui o antigo modelo de sessão única — cada conta tem seu próprio cookie jar
/// isolado (`AccountSession`/`EnjoeiWebSession`) e pode megafonar de forma independente das outras.
@MainActor
@Observable
final class AccountsStore {
    private(set) var accounts: [AccountSession] = []
    private(set) var isRestoring = true
    var isPresentingLogin = false
    private(set) var pendingLoginAccountID: EnjoeiAccountID?

    private let dependenciesFactory: AccountDependenciesFactory
    private let persistence: AccountsPersisting

    init(
        dependenciesFactory: AccountDependenciesFactory? = nil,
        persistence: AccountsPersisting? = nil
    ) {
        self.dependenciesFactory = dependenciesFactory ?? EnjoeiWebSession.makeDependencies
        self.persistence = persistence ?? UserDefaultsAccountsPersistence()
    }

    /// Abertura do app: cada conta salva tem sua WebView de bastidores recriada e conferida contra
    /// os cookies guardados em disco. Uma conta com sessão vencida fica marcada, sem derrubar as
    /// outras — a WebView guarda os cookies em disco, então basta perguntar à página quem é.
    func restoreAccounts() async {
        var restored: [AccountSession] = []
        for record in persistence.loadAccounts() {
            let dependencies = dependenciesFactory(record.id)
            let account = makeAccount(
                id: record.id,
                user: record.user,
                lastRoundSummary: record.lastRoundSummary,
                dependencies: dependencies
            )
            do {
                account.refreshUser(try await dependencies.client.currentUser(reloadingPage: false))
            } catch {
                account.markSessionExpired()
            }
            restored.append(account)
        }
        accounts = restored
        isRestoring = false
    }

    /// Começa o fluxo de adicionar uma conta nova: gera o id que vai virar o `WKWebsiteDataStore`
    /// isolado dela e abre a sheet de login sobre ele.
    @discardableResult
    func beginAddingAccount() -> EnjoeiAccountID {
        let id = EnjoeiAccountID()
        pendingLoginAccountID = id
        isPresentingLogin = true
        return id
    }

    /// Reabre a sheet de login sobre o MESMO id de uma conta com sessão vencida, pra recuperar sem
    /// perder o identifier (e portanto o resumo/posição dela na lista).
    func retryLogin(for accountID: EnjoeiAccountID) {
        pendingLoginAccountID = accountID
        isPresentingLogin = true
    }

    /// Conferência da tela de login, disparada a cada página carregada e pelo botão "já entrei".
    @discardableResult
    func checkLoginFromWebView(accountID: EnjoeiAccountID) async -> LoginOutcome {
        if let existing = accounts.first(where: { $0.id == accountID }) {
            return await recoverSession(existing)
        }
        return await addAccount(id: accountID)
    }

    func logout(accountID: EnjoeiAccountID) async {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        account.runner.cancel()
        await account.clearSession()
        accounts.removeAll { $0.id == accountID }
        persist()
    }

    /// Conta já existente (sessão vencida): reusa o client/webView dela — nunca cria uma segunda
    /// `EnjoeiWebSession` para o mesmo `WKWebsiteDataStore`.
    private func recoverSession(_ account: AccountSession) async -> LoginOutcome {
        do {
            account.refreshUser(try await account.client.currentUser(reloadingPage: true))
            persist()
            finishPresentingLogin()
            return .loggedIn
        } catch {
            return .pending(feedback: EnjoeiLoginFeedback.message(for: error))
        }
    }

    private func addAccount(id: EnjoeiAccountID) async -> LoginOutcome {
        let dependencies = dependenciesFactory(id)
        do {
            let user = try await dependencies.client.currentUser(reloadingPage: true)
            // Mesma conta do Enjoei logada duas vezes por engano: some com a sessão nova recém
            // criada e só atualiza os dados da que já estava na lista. O `WKWebsiteDataStore`
            // recém-criado fica órfão em disco — removê-lo na hora derrubou o app (crash dentro do
            // próprio WebKit ao chamar `remove(forIdentifier:)` logo depois de criar o data store),
            // então não vale o risco: mesmo trade-off já aceito no logout.
            if let duplicate = accounts.first(where: { $0.user.id == user.id }) {
                await dependencies.sessionClearer.clearSession()
                duplicate.refreshUser(user)
                persist()
                finishPresentingLogin()
                return .loggedIn
            }
            accounts.append(makeAccount(id: id, user: user, dependencies: dependencies))
            persist()
            finishPresentingLogin()
            return .loggedIn
        } catch {
            return .pending(feedback: EnjoeiLoginFeedback.message(for: error))
        }
    }

    /// Cria a conta e fia os avisos do runner dela: fim de rodada persiste o resumo (o runner só
    /// sabe observar `phase`, que reseta a cada `start` novo), sessão caída marca a conta.
    private func makeAccount(
        id: EnjoeiAccountID,
        user: EnjoeiUser,
        lastRoundSummary: MegaphoneRoundSummary? = nil,
        dependencies: AccountDependencies
    ) -> AccountSession {
        let account = AccountSession(
            id: id,
            user: user,
            lastRoundSummary: lastRoundSummary,
            dependencies: dependencies
        )
        account.runner.onRoundFinished = { [weak self, weak account] summary in
            account?.applyRoundFinished(summary)
            self?.persist()
        }
        account.runner.onSessionExpired = { [weak account] in
            account?.markSessionExpired()
        }
        return account
    }

    private func finishPresentingLogin() {
        isPresentingLogin = false
        pendingLoginAccountID = nil
    }

    private func persist() {
        persistence.save(accounts.map(\.record))
    }
}
