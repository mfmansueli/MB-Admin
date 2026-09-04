import Foundation
import Observation

/// Fila de ações entre contas: posta (numa conta diferente, ou reposta na mesma), apaga, inativa
/// ou ativa um produto de cada vez, respeitando `interval` entre uma ação e a próxima — o mesmo
/// intervalo pras quatro, `.post` incluído (ver `waitInterval`). Também é o único ponto de entrada
/// pra postar — tanto a fila quanto o botão avulso "postar em X" de uma linha passam por aqui, pra
/// `currentItem` sempre refletir o que está em voo agora, esteja vindo da fila ou não.
@MainActor
@Observable
final class PostQueue {
    /// Restaurado de disco no `init` — só os itens que ainda estavam pendentes (nunca chegaram a
    /// terminar) sobrevivem a fechar e abrir o app de novo; ver `persistPendingItems`.
    private(set) var items: [PostQueueItem] = []
    /// Ações já concluídas (sucesso ou erro), mais recente primeiro — sobrevive à remoção do item
    /// da fila e a fechar/abrir o app de novo, ao contrário de `items`. Ver `recordHistory`.
    private(set) var history: [PostHistoryEntry] = []
    private(set) var isRunning = false
    /// Pausa pedida pelo usuário — o laço espera aqui antes de começar o próximo item; o item em
    /// voo no momento da pausa termina normalmente.
    private(set) var isPaused = false
    /// O item em voo agora (chamada de rede rolando) — fila ou postagem avulsa — pra
    /// `AccountRowView` saber se a conta dela é origem ou destino dele.
    private(set) var currentItem: PostQueueItem?
    /// Quando a próxima ação da fila deve começar — só setado durante `waitInterval` (entre uma
    /// ação e a próxima), `nil` o resto do tempo (nada em espera agora: parado, pausado, ou uma
    /// ação já em voo). Recalculado a cada pedaço de 0.2s com o `interval` atual, então reflete uma
    /// troca de intervalo em andamento na hora — pra `PostQueueView` mostrar a contagem regressiva
    /// de verdade, em vez do cooldown fixo do `CrossAccountPoster` de antes.
    private(set) var nextActionAt: Date?
    /// Só pro caso "a conta de origem ou destino não existe mais quando a vez do item chega".
    private var failureOverrides: [UUID: String] = [:]
    private var task: Task<Void, Never>?
    private var pauseGate: CheckedContinuation<Void, Never>?

    private let poster: CrossAccountPoster
    private let historyPersistence: PostHistoryPersisting
    private let itemsPersistence: PostQueueItemsPersisting
    private let defaults: UserDefaults
    /// `var`, não `let`: quem cria a fila às vezes não pode capturar `self` no provider ainda
    /// (dentro do próprio `init` de quem a possui) e liga ele de verdade logo em seguida.
    var accountsProvider: () -> [AccountSession]
    /// Intervalo entre uma ação da fila e a próxima — a tela deixa o usuário escolher entre 30s e
    /// 5 minutos, `run()` lê o valor atual a cada volta do laço (a mudança já vale a partir da
    /// próxima espera), e a escolha sobrevive a fechar e abrir o app de novo (ver `setInterval`).
    /// Só mutável por aqui dentro — `setInterval` é quem persiste, então a UI nunca atribui direto.
    private(set) var interval: TimeInterval

    private static let intervalDefaultsKey = "postQueue.interval"

    init(
        poster: CrossAccountPoster,
        accountsProvider: @escaping () -> [AccountSession],
        interval: TimeInterval? = nil,
        historyPersistence: PostHistoryPersisting = InMemoryPostHistoryPersistence(),
        itemsPersistence: PostQueueItemsPersisting = InMemoryPostQueueItemsPersistence(),
        defaults: UserDefaults = .standard
    ) {
        self.poster = poster
        self.accountsProvider = accountsProvider
        self.historyPersistence = historyPersistence
        self.itemsPersistence = itemsPersistence
        self.defaults = defaults
        history = historyPersistence.loadEntries()
        // Um `interval` explícito (testes, sobretudo) vale por cima de qualquer coisa persistida.
        // Sem ele, a última escolha do usuário — se existir — prevalece sobre o cooldown padrão do
        // `poster`.
        if let interval {
            self.interval = interval
        } else {
            let stored = defaults.double(forKey: Self.intervalDefaultsKey)
            self.interval = stored > 0 ? stored : poster.cooldownDuration
        }
        items = itemsPersistence.loadItems()
        // Recupera pausada de propósito, nunca processando sozinha: reabrir o app não é o mesmo
        // que o usuário confirmar que quer continuar — em especial pra `.post`, onde repetir por
        // engano a ação que estava em voo na hora do fechamento criaria um anúncio duplicado.
        // `isPaused = true` antes de `startIfNeeded()` faz o laço nascer e travar direto em
        // `waitWhilePaused()`, esperando o toque em "continuar" (mesmo mecanismo de uma pausa
        // pedida em tela, sem precisar de um estado à parte).
        if !items.isEmpty {
            isPaused = true
            startIfNeeded()
        }
    }

    /// Muda o intervalo entre ações e já persiste a escolha — chamado pelo menu de intervalo da
    /// fila (`PostQueueView`), pra sobreviver a fechar e abrir o app de novo.
    func setInterval(_ newValue: TimeInterval) {
        interval = newValue
        defaults.set(newValue, forKey: Self.intervalDefaultsKey)
    }

    func status(for item: PostQueueItem) -> MegaphoneStatus {
        if let message = failureOverrides[item.id] { return .failed(message) }
        switch item.kind {
        case .post:
            return poster.statuses[item.postTarget] ?? .pending
        case .delete:
            guard let account = accountsProvider().first(where: { $0.id == item.sourceAccountID }) else {
                return .pending
            }
            return account.runner.deleteStatuses[item.product.id] ?? .pending
        case .inactivate:
            guard let account = accountsProvider().first(where: { $0.id == item.sourceAccountID }) else {
                return .pending
            }
            return account.runner.inactivateStatuses[item.product.id] ?? .pending
        case .activate:
            guard let account = accountsProvider().first(where: { $0.id == item.sourceAccountID }) else {
                return .pending
            }
            return account.runner.activateStatuses[item.product.id] ?? .pending
        }
    }

    /// Diagnóstico completo por trás de `status(for:)`, quando ela é `.failed` — mesma fonte por
    /// trás de cada `case` (o `poster` compartilhado pra postar, o `runner` da própria conta pras
    /// outras três ações). Uma conta que sumiu da lista (`failureOverrides`) não tem `Error` real
    /// por trás, só a mensagem sintética.
    func failureDetail(for item: PostQueueItem) -> MegaphoneFailureDetail? {
        if let message = failureOverrides[item.id] {
            return MegaphoneFailureDetail(action: MegaphoneFailureDetail.Action(kind: item.kind), syntheticMessage: message)
        }
        switch item.kind {
        case .post:
            return poster.failureDetails[item.postTarget]
        case .delete, .inactivate, .activate:
            guard let account = accountsProvider().first(where: { $0.id == item.sourceAccountID }) else {
                return nil
            }
            return account.runner.failureDetails[item.product.id]
        }
    }

    func enqueue(product: EnjoeiProduct, source: AccountSession, destination: AccountSession) {
        items.append(
            PostQueueItem(
                id: UUID(),
                product: product,
                sourceAccountID: source.id,
                sourceAccountName: source.user.name,
                destinationAccountID: destination.id,
                destinationAccountName: destination.user.name
            )
        )
        persistPendingItems()
        startIfNeeded()
    }

    /// Apaga um produto pela fila, em vez de na hora — mesma pacing/visibilidade das postagens.
    /// Só uma conta está envolvida; origem e destino ficam iguais só pra reaproveitar o formato de
    /// `PostQueueItem` (`kind: .delete` é quem diz pra UI que não é uma postagem de verdade).
    func enqueueDelete(product: EnjoeiProduct, account: AccountSession) {
        items.append(
            PostQueueItem(
                id: UUID(),
                product: product,
                kind: .delete,
                sourceAccountID: account.id,
                sourceAccountName: account.user.name,
                destinationAccountID: account.id,
                destinationAccountName: account.user.name
            )
        )
        persistPendingItems()
        startIfNeeded()
    }

    /// Inativa um produto pela fila — sai da vitrine de publicados sem apagar de vez, e (ao
    /// contrário de `enqueueDelete`) dá pra reverter mais tarde direto no Enjoei. Mesmo raciocínio
    /// de origem/destino iguais que `enqueueDelete`.
    func enqueueInactivate(product: EnjoeiProduct, account: AccountSession) {
        items.append(
            PostQueueItem(
                id: UUID(),
                product: product,
                kind: .inactivate,
                sourceAccountID: account.id,
                sourceAccountName: account.user.name,
                destinationAccountID: account.id,
                destinationAccountName: account.user.name
            )
        )
        persistPendingItems()
        startIfNeeded()
    }

    /// Ativa de novo um produto inativado, pela fila — usado a partir da aba "inativos". Mesmo
    /// raciocínio de origem/destino iguais que `enqueueDelete`/`enqueueInactivate`.
    func enqueueActivate(product: EnjoeiProduct, account: AccountSession) {
        items.append(
            PostQueueItem(
                id: UUID(),
                product: product,
                kind: .activate,
                sourceAccountID: account.id,
                sourceAccountName: account.user.name,
                destinationAccountID: account.id,
                destinationAccountName: account.user.name
            )
        )
        persistPendingItems()
        startIfNeeded()
    }

    /// Não cancela uma chamada de rede já em voo (deixa terminar sozinha) — só tira o item da
    /// lista e da vez dele na fila.
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persistPendingItems()
    }

    /// Tira tudo da fila de uma vez — pro botão "limpar fila". Mesmo raciocínio do `remove(id:)`:
    /// uma chamada de rede já em voo termina sozinha, só não sobra nada pro laço processar depois
    /// dela.
    func removeAll() {
        items.removeAll()
        persistPendingItems()
    }

    /// Apaga o histórico salvo — não afeta a fila ativa (`items`), só o registro persistido de
    /// ações já concluídas.
    func clearHistory() {
        history.removeAll()
        historyPersistence.clear()
    }

    /// Pausa a fila — um item em andamento (a chamada de rede já disparada) termina normalmente;
    /// o intervalo de espera logo depois dele é interrompido na hora (ver `waitInterval`), e o item
    /// seguinte, ainda não escolhido, fica esperando. Não afeta `postSingle`, que continua
    /// funcionando mesmo com a fila pausada (é uma ação direta do usuário numa linha específica,
    /// fora do laço automático).
    func pause() {
        guard !isPaused else { return }
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        openPauseGate()
    }

    /// Postagem avulsa — o botão "postar em X" de uma linha da comparação chama isso em vez de
    /// `poster.post` direto, só pra também virar `currentItem` (e aparecer na row da conta)
    /// enquanto estiver em voo. Não entra em `items`: não é fila.
    func postSingle(product: EnjoeiProduct, from source: AccountSession, to destination: AccountSession) {
        let target = PostTarget(productID: product.id, destinationAccountID: destination.id)
        guard currentItem == nil,
              poster.statuses[target] != .megaphoning,
              poster.statuses[target] != .succeeded else { return }
        let item = PostQueueItem(
            id: UUID(),
            product: product,
            sourceAccountID: source.id,
            sourceAccountName: source.user.name,
            destinationAccountID: destination.id,
            destinationAccountName: destination.user.name
        )
        // Reservado na hora, antes de qualquer suspensão — a Task abaixo só roda depois que o
        // código síncrono atual termina, então sem isso aqui um segundo toque quase junto (antes
        // da Task começar) passaria pelo guard de cima vendo `currentItem` ainda vazio.
        currentItem = item
        Task { [weak self] in
            await self?.postAndTrack(item: item, source: source, destination: destination)
        }
    }

    private func startIfNeeded() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
            self?.isRunning = false
        }
    }

    private func run() async {
        while true {
            // Antes de escolher o próximo item, não durante um já em voo — pausar não interrompe
            // uma chamada de rede que já começou, só a espera de escolher a seguinte.
            await waitWhilePaused()
            guard let item = items.first(where: { status(for: $0) == .pending }) else { return }
            guard let source = accountsProvider().first(where: { $0.id == item.sourceAccountID }) else {
                failureOverrides[item.id] = "conta não está mais logada"
                persistPendingItems()
                continue
            }
            switch item.kind {
            case .post:
                guard let destination = accountsProvider().first(where: { $0.id == item.destinationAccountID }) else {
                    failureOverrides[item.id] = "conta não está mais logada"
                    persistPendingItems()
                    continue
                }
                // Sem esperar `poster.isInCooldown` aqui de propósito: quem manda na pacing de uma
                // ação vinda da fila é só `interval` (`waitInterval`, logo abaixo), igual às outras
                // três — o cooldown fixo do `CrossAccountPoster` virou só um sinal pra UI da
                // postagem avulsa (`UnmatchedProductRowView`), não bloqueia mais nada aqui.
                await postAndTrack(item: item, source: source, destination: destination)
            case .delete:
                await deleteAndTrack(item: item, account: source)
            case .inactivate:
                await inactivateAndTrack(item: item, account: source)
            case .activate:
                await activateAndTrack(item: item, account: source)
            }
            if items.contains(where: { status(for: $0) == .pending }) {
                await waitInterval()
            }
        }
    }

    /// Espera o intervalo entre uma ação e a próxima, em pedaços curtos — pausar durante essa
    /// espera larga ela na hora (dentro de um pedaço) em vez de deixar o resto do intervalo correr
    /// escondido atrás da mesma UI de "pausado"; `waitWhilePaused`, logo na volta ao topo do laço,
    /// é quem de fato prende até o `resume()`. Mesmo raciocínio pra `interval`: lido de novo a cada
    /// pedaço (não guardado numa variável local no começo da espera), pra trocar o intervalo
    /// preferido enquanto a fila já está esperando também valer na hora, dentro de um pedaço — sem
    /// isso, a troca só valeria a partir da espera seguinte, deixando a impressão de que o app
    /// ignorou a escolha nova até 5 minutos depois.
    private func waitInterval() async {
        let start = Date()
        defer { nextActionAt = nil }
        while !isPaused {
            let remaining = interval - Date().timeIntervalSince(start)
            guard remaining > 0 else { return }
            nextActionAt = Date().addingTimeInterval(remaining)
            try? await Task.sleep(for: .seconds(min(0.2, remaining)))
        }
    }

    private func waitWhilePaused() async {
        while isPaused {
            await withCheckedContinuation { continuation in
                pauseGate = continuation
            }
        }
    }

    private func openPauseGate() {
        pauseGate?.resume()
        pauseGate = nil
    }

    /// Núcleo compartilhado entre fila e avulso: marca `currentItem`, posta e espera terminar de
    /// verdade (`poster.postAndWait`, não um laço checando `statuses` — `run(...)` por trás já
    /// deixa o status resolvido antes de voltar).
    private func postAndTrack(item: PostQueueItem, source: AccountSession, destination: AccountSession) async {
        currentItem = item
        await poster.postAndWait(product: item.product, from: source, to: destination)
        if currentItem?.id == item.id {
            currentItem = nil
        }
        recordHistory(item: item)
        persistPendingItems()
    }

    /// Delega a exclusão de verdade pro `MegaphoneRunner` da própria conta — ele já sabe renovar
    /// token CSRF e marcar `deleteStatuses`, que é a mesma fonte que a linha do produto usa pra se
    /// mostrar apagada. A fila só decide a vez de cada item.
    private func deleteAndTrack(item: PostQueueItem, account: AccountSession) async {
        currentItem = item
        await account.runner.deleteProductAndWait(productID: item.product.id)
        if currentItem?.id == item.id {
            currentItem = nil
        }
        recordHistory(item: item)
        persistPendingItems()
    }

    /// Mesma ideia de `deleteAndTrack`, delegando pro `MegaphoneRunner` da conta — ele já sabe ler
    /// o produto inteiro e reenviar com `product_state: disable`.
    private func inactivateAndTrack(item: PostQueueItem, account: AccountSession) async {
        currentItem = item
        await account.runner.inactivateProductAndWait(productID: item.product.id)
        if currentItem?.id == item.id {
            currentItem = nil
        }
        recordHistory(item: item)
        persistPendingItems()
    }

    /// Mesma ideia de `inactivateAndTrack`, delegando pro `MegaphoneRunner` da conta pra reenviar
    /// com `product_state: active`.
    private func activateAndTrack(item: PostQueueItem, account: AccountSession) async {
        currentItem = item
        await account.runner.activateProductAndWait(productID: item.product.id)
        if currentItem?.id == item.id {
            currentItem = nil
        }
        recordHistory(item: item)
        persistPendingItems()
    }

    /// Guarda no histórico persistido, mais recente primeiro — chamado pelos quatro `xAndTrack`
    /// logo depois que a chamada de rede de verdade termina. `status(for:)` ainda `.pending`/
    /// `.megaphoning` (ex.: item substituído por outro com o mesmo id antes da rede responder) não
    /// vira entrada nenhuma, defensivamente. Grava só a entrada nova (`insert`, não reescreve o
    /// histórico inteiro) — ver `PostHistoryPersisting`.
    private func recordHistory(item: PostQueueItem) {
        guard let outcome = PostHistoryEntry.Outcome(status: status(for: item)) else { return }
        let entry = PostHistoryEntry(
            id: item.id,
            product: item.product,
            kind: item.kind,
            sourceAccountID: item.sourceAccountID,
            sourceAccountName: item.sourceAccountName,
            destinationAccountID: item.destinationAccountID,
            destinationAccountName: item.destinationAccountName,
            outcome: outcome,
            completedAt: .now,
            failureDetail: outcome == .succeeded ? nil : failureDetail(for: item)
        )
        history.insert(entry, at: 0)
        historyPersistence.insert(entry)
    }

    /// Guarda em disco só os itens ainda `.pending` — os concluídos (sucesso ou erro) não
    /// precisam sobreviver ao fechar o app: já foram gravados em `history` por `recordHistory`, e
    /// tentar de novo uma ação que já rodou (em especial `.post`, que criaria um anúncio duplicado)
    /// é exatamente o que essa exclusão evita. Chamado a cada mudança que afeta quais itens contam
    /// como pendentes: enfileirar, remover, e o fim de cada ação (sucesso, erro ou conta deslogada).
    private func persistPendingItems() {
        itemsPersistence.saveItems(items.filter { status(for: $0) == .pending })
    }
}
