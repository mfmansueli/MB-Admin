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
    /// Espelho da seleção da barra lateral (`AccountsListView`) — só pra `releaseIdleAccountsMemory()`
    /// nunca liberar memória da conta que o usuário está olhando agora (evita um recarregamento de
    /// página visível na próxima ação dela). Não é a fonte da verdade da seleção em si, que continua
    /// sendo o `@State` da própria `AccountsListView`.
    var selectedAccountID: EnjoeiAccountID?

    /// Compartilhado entre a tela de comparação (postagem avulsa) e a fila de ações — as duas
    /// precisam respeitar o mesmo bloqueio entre uma postagem e a próxima.
    let poster = CrossAccountPoster()
    let postQueue: PostQueue
    /// Compartilhada entre todas as contas (ver `MegaphoneQueue`) — sem limite de propósito: agora
    /// que a listagem de produtos não passa mais por `List`/`NSTableView` (ver
    /// `AccountPublishedTabView.productList`), o gargalo que motivava travar tudo numa conta de cada
    /// vez deixou de existir. Se voltar a travar com várias contas megafonando juntas, é só baixar
    /// esse número de novo.
    let megaphoneQueue = MegaphoneQueue(concurrencyLimit: .max)
    /// A Live Activity de cada conta megafonando (tela bloqueada e Dynamic Island) — ver
    /// `MegaphoneLiveActivities`.
    let liveActivities = MegaphoneLiveActivities()

    private let dependenciesFactory: AccountDependenciesFactory
    private let persistence: AccountsPersisting
    /// Rede de segurança automática pro `megaphoneQueue` acima ficar sem limite de propósito — ver
    /// `MegaphoneQueue.applyMemoryPressureCap(_:)`.
    private let memoryPressureObserver: any MemoryPressureObserving

    /// Se um aviso de memória limita a `megaphoneQueue` a uma conta por vez — só fora do Mac. No
    /// iPhone/iPad o aviso é sobre o próprio app, perto de ser encerrado pelo sistema, e é esse o
    /// cenário que o teto protege. No Mac (Catalyst) o aviso reflete a pressão do sistema inteiro
    /// (outros apps abertos contam) e chega com frequência mesmo com o app longe de qualquer
    /// risco — com o teto valendo lá, a terceira loja ficava presa em "esperando a vez" até as
    /// outras duas terminarem (pra sempre, com rodadas infinitas), que é justamente o que
    /// `concurrencyLimit: .max` decidiu não fazer.
    private static var memoryWarningCapsMegaphoneQueueByDefault: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        true
        #endif
    }

    /// - Parameter memoryWarningCapsMegaphoneQueue: `nil` usa o padrão da plataforma (ver
    ///   `memoryWarningCapsMegaphoneQueueByDefault`); os testes fixam o valor pra não depender de
    ///   onde rodam.
    init(
        dependenciesFactory: AccountDependenciesFactory? = nil,
        persistence: AccountsPersisting? = nil,
        postHistoryPersistence: PostHistoryPersisting? = nil,
        postQueueItemsPersistence: PostQueueItemsPersisting? = nil,
        memoryPressureObserver: (any MemoryPressureObserving)? = nil,
        memoryWarningCapsMegaphoneQueue: Bool? = nil
    ) {
        self.dependenciesFactory = dependenciesFactory ?? EnjoeiWebSession.makeDependencies
        self.persistence = persistence ?? UserDefaultsAccountsPersistence()
        self.memoryPressureObserver = memoryPressureObserver ?? SystemMemoryPressureObserver()
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
        // Os botões de pausar/parar da Live Activity rodam no processo do app, mas não enxergam as
        // contas — chegam aqui pelo id.
        MegaphoneLiveActivityCommands.shared.handler = { [weak self] command, accountID in
            self?.handleLiveActivityCommand(command, accountID: accountID)
        }
        // Nunca aborta quem já está megafonando (ver o doc de `applyMemoryPressureCap`) — só evita
        // que contas novas comecem enquanto o aviso estiver de pé. `megaphoneQueue` já existe aqui
        // (inicializado por cima, sem depender de `self`).
        let capsMegaphoneQueue = memoryWarningCapsMegaphoneQueue ?? Self.memoryWarningCapsMegaphoneQueueByDefault
        self.memoryPressureObserver.onMemoryWarning = { [weak self] in
            if capsMegaphoneQueue {
                self?.megaphoneQueue.applyMemoryPressureCap(1)
            }
            self?.releaseIdleAccountsMemory()
        }
        self.memoryPressureObserver.start()
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
            dependencies: dependencies,
            megaphoneQueue: megaphoneQueue
        )
        account.runner.onRoundFinished = { [weak self, weak account] summary in
            account?.applyRoundFinished(summary)
            self?.persist()
        }
        account.runner.onSessionExpired = { [weak account] in
            account?.markSessionExpired()
        }
        account.runner.onProgressSnapshotChange = { [weak self, weak account] snapshot in
            guard let account else { return }
            self?.liveActivities.apply(snapshot, accountID: account.id, accountName: account.user.name)
        }
        return account
    }

    /// Mesmo efeito dos botões do painel do megafone na tela da conta.
    private func handleLiveActivityCommand(_ command: MegaphoneLiveActivityCommands.Command, accountID: EnjoeiAccountID) {
        guard let runner = accounts.first(where: { $0.id == accountID })?.runner else { return }
        switch command {
        case .togglePause:
            if runner.isPaused {
                runner.resume()
            } else {
                runner.pause()
            }
        case .stop:
            runner.cancel()
        }
    }

    private func finishPresentingLogin() {
        isPresentingLogin = false
        pendingLoginAccountID = nil
    }

    /// Sob aviso real de pressão de memória (nunca proativamente — sem timer de inatividade nenhum),
    /// libera a página de bastidores das contas que não são a selecionada, não estão com o megafone
    /// rodando ou esperando a vez, e não têm nenhum outro carregamento pausado-mas-em-andamento (ver
    /// `EnjoeiClientProtocol.releaseMemoryIfIdle()`). A checagem aqui é só uma heurística de "vale a
    /// pena tentar" — quem garante que isso nunca acontece no meio de uma chamada de rede já em voo é
    /// o contador dentro de `EnjoeiWebSession`, não esta lista.
    ///
    /// Os quatro carregamentos abaixo (produto por produto ou página por página, sempre com uma
    /// pausa entre uma chamada e a próxima) passam por um instante com nenhuma chamada em voo mesmo
    /// no meio de um carregamento longe de terminar — bem na pausa. Sem checá-los aqui, um aviso de
    /// memória caindo numa dessas pausas (algo comum com o Mac sob pressão real, que é justamente
    /// quando este método roda) mandava a página pra `about:blank` no meio da busca; a chamada
    /// seguinte do mesmo laço então recarregava a página de verdade antes de continuar — e trocar de
    /// origem assim (`about:blank` ↔ enjoei.com.br) repetidas vezes faz o WebKit abrir um processo
    /// `WebContent` novo em vez de reaproveitar o existente. Visto ao vivo (`ps`/`sample`) derrubando
    /// vários processos novos em poucos minutos com a tela de comparação em "comparação completa".
    private func isEligibleForMemoryRelease(_ account: AccountSession) -> Bool {
        account.id != selectedAccountID
            && !account.runner.isRunning
            && !megaphoneQueue.isWaiting(account.runner)
            && !account.productDetailsLoader.isRunning
            && !account.inactiveProductsLoader.isLoadingPage
            && !account.smartPriceProductsLoader.isLoadingPage
            && !account.smartPriceProductsLoader.isProcessingActivations
    }

    private func releaseIdleAccountsMemory() {
        for account in accounts where isEligibleForMemoryRelease(account) {
            Task { await account.client.releaseMemoryIfIdle() }
        }
    }

    private func persist() {
        persistence.save(accounts.map(\.record))
    }
}
