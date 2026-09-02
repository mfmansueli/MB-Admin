import Foundation
import Observation

/// Fila de ações entre contas: posta (numa conta diferente, ou reposta na mesma) ou apaga um
/// produto de cada vez, respeitando o mesmo intervalo do `CrossAccountPoster` entre uma postagem e
/// a próxima. Também é o único ponto de entrada pra postar — tanto a fila quanto o botão avulso
/// "postar em X" de uma linha passam por aqui, pra `currentItem` sempre refletir o que está em voo
/// agora, esteja vindo da fila ou não.
@MainActor
@Observable
final class PostQueue {
    private(set) var items: [PostQueueItem] = []
    private(set) var isRunning = false
    /// Pausa pedida pelo usuário — o laço espera aqui antes de começar o próximo item; o item em
    /// voo no momento da pausa termina normalmente.
    private(set) var isPaused = false
    /// O item em voo agora (chamada de rede rolando) — fila ou postagem avulsa — pra
    /// `AccountRowView` saber se a conta dela é origem ou destino dele.
    private(set) var currentItem: PostQueueItem?
    /// Só pro caso "a conta de origem ou destino não existe mais quando a vez do item chega".
    private var failureOverrides: [UUID: String] = [:]
    private var task: Task<Void, Never>?
    private var pauseGate: CheckedContinuation<Void, Never>?

    private let poster: CrossAccountPoster
    /// `var`, não `let`: quem cria a fila às vezes não pode capturar `self` no provider ainda
    /// (dentro do próprio `init` de quem a possui) e liga ele de verdade logo em seguida.
    var accountsProvider: () -> [AccountSession]
    /// Inicializado a partir do intervalo do `poster` compartilhado (ou injetado, só pros testes
    /// não esperarem o intervalo de verdade) — mas depois disso é um `var` de verdade: a tela da
    /// fila deixa o usuário reconfigurar entre 1 e 5 minutos, e `run()` lê o valor atual a cada
    /// volta do laço, então a mudança já vale a partir da próxima espera entre ações.
    var interval: TimeInterval

    init(
        poster: CrossAccountPoster,
        accountsProvider: @escaping () -> [AccountSession],
        interval: TimeInterval? = nil
    ) {
        self.poster = poster
        self.accountsProvider = accountsProvider
        self.interval = interval ?? poster.cooldownDuration
    }

    func status(for item: PostQueueItem) -> MegaphoneStatus {
        if let message = failureOverrides[item.id] { return .failed(message) }
        switch item.kind {
        case .post:
            return poster.statuses[item.product.id] ?? .pending
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
        startIfNeeded()
    }

    /// Não cancela uma chamada de rede já em voo (deixa terminar sozinha) — só tira o item da
    /// lista e da vez dele na fila.
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Tira tudo da fila de uma vez — pro botão "limpar fila". Mesmo raciocínio do `remove(id:)`:
    /// uma chamada de rede já em voo termina sozinha, só não sobra nada pro laço processar depois
    /// dela.
    func removeAll() {
        items.removeAll()
    }

    /// Pausa a fila — um item em andamento (incluindo o intervalo de espera logo depois dele)
    /// termina normalmente; só o item seguinte, ainda não escolhido, fica esperando. Não afeta
    /// `postSingle`, que continua funcionando mesmo com a fila pausada (é uma ação direta do
    /// usuário numa linha específica, fora do laço automático).
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
        guard currentItem == nil,
              poster.statuses[product.id] != .megaphoning,
              poster.statuses[product.id] != .succeeded else { return }
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
                continue
            }
            switch item.kind {
            case .post:
                guard let destination = accountsProvider().first(where: { $0.id == item.destinationAccountID }) else {
                    failureOverrides[item.id] = "conta não está mais logada"
                    continue
                }
                // Uma postagem avulsa pode ter acabado de deixar o poster compartilhado em
                // cooldown — espera passar antes de tentar, senão `poster.post` vira no-op.
                while poster.isInCooldown {
                    try? await Task.sleep(for: .seconds(1))
                }
                await postAndTrack(item: item, source: source, destination: destination)
            case .delete:
                // Apagar não passa pelo cooldown de postagem — são rotas diferentes do Enjoei, sem
                // relação com o limite de criar produtos.
                await deleteAndTrack(item: item, account: source)
            case .inactivate:
                // Mesmo raciocínio de `.delete`: rota diferente, sem relação com o cooldown de
                // postagem.
                await inactivateAndTrack(item: item, account: source)
            case .activate:
                await activateAndTrack(item: item, account: source)
            }
            if items.contains(where: { status(for: $0) == .pending }) {
                try? await Task.sleep(for: .seconds(interval))
            }
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

    /// Núcleo compartilhado entre fila e avulso: marca `currentItem`, dispara `poster.post` e só
    /// libera `currentItem` quando aquele status sair de `.megaphoning`.
    private func postAndTrack(item: PostQueueItem, source: AccountSession, destination: AccountSession) async {
        currentItem = item
        poster.post(product: item.product, from: source, to: destination)
        while poster.statuses[item.product.id] == .megaphoning {
            await Task.yield()
        }
        if currentItem?.id == item.id {
            currentItem = nil
        }
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
    }

    /// Mesma ideia de `deleteAndTrack`, delegando pro `MegaphoneRunner` da conta — ele já sabe ler
    /// o produto inteiro e reenviar com `product_state: disable`.
    private func inactivateAndTrack(item: PostQueueItem, account: AccountSession) async {
        currentItem = item
        await account.runner.inactivateProductAndWait(productID: item.product.id)
        if currentItem?.id == item.id {
            currentItem = nil
        }
    }

    /// Mesma ideia de `inactivateAndTrack`, delegando pro `MegaphoneRunner` da conta pra reenviar
    /// com `product_state: active`.
    private func activateAndTrack(item: PostQueueItem, account: AccountSession) async {
        currentItem = item
        await account.runner.activateProductAndWait(productID: item.product.id)
        if currentItem?.id == item.id {
            currentItem = nil
        }
    }
}
