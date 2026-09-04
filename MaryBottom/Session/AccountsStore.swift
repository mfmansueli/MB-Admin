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

    /// Compartilhado entre a tela de comparação (postagem avulsa) e a fila de ações — as duas
    /// precisam respeitar o mesmo bloqueio entre uma postagem e a próxima.
    let poster = CrossAccountPoster()
    let postQueue: PostQueue

    private let dependenciesFactory: AccountDependenciesFactory
    private let persistence: AccountsPersisting

    init(
        dependenciesFactory: AccountDependenciesFactory? = nil,
        persistence: AccountsPersisting? = nil,
        postHistoryPersistence: PostHistoryPersisting? = nil,
        postQueueItemsPersistence: PostQueueItemsPersisting? = nil
    ) {
        self.dependenciesFactory = dependenciesFactory ?? EnjoeiWebSession.makeDependencies
        self.persistence = persistence ?? UserDefaultsAccountsPersistence()
        // Construído sem capturar `self` (o compilador recusa isso antes do `init` terminar) — o
        // provider de verdade é ligado logo abaixo, já com `self` totalmente inicializado. Se
        // houver itens pendentes restaurados, `PostQueue.init` já começa a fila (pausada, esperando
        // o toque em "continuar") antes dessa troca — sem problema: nada roda de verdade até a
        // pausa ser desfeita, bem depois deste `init` terminar.
        postQueue = PostQueue(
            poster: poster,
            accountsProvider: { [] },
            historyPersistence: postHistoryPersistence ?? SwiftDataPostHistoryPersistence(),
            itemsPersistence: postQueueItemsPersistence ?? UserDefaultsPostQueueItemsPersistence()
        )
        postQueue.accountsProvider = { [weak self] in self?.accounts ?? [] }
    }

    /// Abertura do app: cada conta salva tem sua WebView de bastidores recriada e conferida contra
    /// os cookies guardados em disco — em paralelo entre as contas (cada uma tem sua própria
    /// WebView, sem estado compartilhado com as outras), pra abrir o app com várias contas salvas
    /// não demorar a soma de todas, só a mais lenta delas.
    func restoreAccounts() async {
        let records = persistence.loadAccounts()
        let restored = await withTaskGroup(of: (Int, AccountSession?).self) { group in
            for (index, record) in records.enumerated() {
                group.addTask { [weak self] in
                    (index, await self?.restoreAccount(record: record))
                }
            }
            var results: [(Int, AccountSession?)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        // A ordem de conclusão de cada conta não segue a ordem persistida (a mais rápida termina
        // primeiro) — reordena pelo índice original antes de publicar, senão a lista pula de
        // posição a cada abertura do app.
        accounts = restored.sorted { $0.0 < $1.0 }.compactMap(\.1)
        isRestoring = false
    }

    /// Confere uma conta salva contra o cookie guardado em disco. Sessão realmente vencida
    /// (`notAuthenticated`) marca como tal; qualquer outro erro (rede instável, Enjoei fora do ar
    /// no momento) vira `checkFailed` em vez de pedir login de novo à toa por uma falha passageira
    /// bem na abertura do app.
    private func restoreAccount(record: AccountRecord) async -> AccountSession {
        let dependencies = dependenciesFactory(record.id)
        let account = makeAccount(
            id: record.id,
            user: record.user,
            lastRoundSummary: record.lastRoundSummary,
            dependencies: dependencies
        )
        do {
            account.refreshUser(try await dependencies.client.currentUser(reloadingPage: false))
        } catch EnjoeiError.notAuthenticated {
            account.markSessionExpired()
        } catch {
            account.markCheckFailed()
        }
        return account
    }

    /// Tenta de novo a confirmação de uma conta que ficou `checkFailed` no restore — sem refazer a
    /// lista inteira, e sem mexer nas outras contas.
    func retryCheckingSession(for accountID: EnjoeiAccountID) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        Task { [weak account] in
            guard let account else { return }
            do {
                account.refreshUser(try await account.client.currentUser(reloadingPage: false))
            } catch EnjoeiError.notAuthenticated {
                account.markSessionExpired()
            } catch {
                account.markCheckFailed()
            }
        }
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
        clearLocalData(accountID: accountID)
        persist()
    }

    /// Sem isso, a lista de publicados, a de inativos e as preferências de rodada/intervalo/aba/
    /// filtro da conta ficam órfãs em disco pra sempre — o id nunca mais aparece em `accounts` pra
    /// alguém vir apagar depois. `PerAccountModelContainer.destroy` apaga o arquivo inteiro das
    /// três listas de uma vez (elas moram juntas no container dessa conta — ver esse tipo), não
    /// precisa mais zerar uma por uma.
    private func clearLocalData(accountID: EnjoeiAccountID) {
        PerAccountModelContainer.destroy(for: accountID)
        // Mesmas chaves que `AccountPublishedTabView`/`AccountDetailView` montam em `@AppStorage`
        // — não tem como reusar a property wrapper daqui, só reconstruir a mesma string.
        UserDefaults.standard.removeObject(forKey: "megaphone.rounds.\(accountID)")
        UserDefaults.standard.removeObject(forKey: "megaphone.speed.\(accountID)")
        UserDefaults.standard.removeObject(forKey: "accountDetail.selectedTab.\(accountID)")
        UserDefaults.standard.removeObject(forKey: "accountDetail.filter.\(accountID)")
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
