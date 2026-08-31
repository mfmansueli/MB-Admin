import Foundation
import Observation

/// Fila de publicação entre contas: processa um produto de cada vez, respeitando o mesmo
/// intervalo do `CrossAccountPoster` entre uma postagem e a próxima. Também é o único ponto de
/// entrada pra postar — tanto a fila quanto o botão avulso "postar em X" de uma linha passam por
/// aqui, pra `currentItem` sempre refletir o que está em voo agora, esteja vindo da fila ou não.
@MainActor
@Observable
final class PostQueue {
    private(set) var items: [PostQueueItem] = []
    private(set) var isRunning = false
    /// O item em voo agora (chamada de rede rolando) — fila ou postagem avulsa — pra
    /// `AccountRowView` saber se a conta dela é origem ou destino dele.
    private(set) var currentItem: PostQueueItem?
    /// Só pro caso "a conta de origem ou destino não existe mais quando a vez do item chega".
    private var failureOverrides: [UUID: String] = [:]
    private var task: Task<Void, Never>?

    private let poster: CrossAccountPoster
    /// `var`, não `let`: quem cria a fila às vezes não pode capturar `self` no provider ainda
    /// (dentro do próprio `init` de quem a possui) e liga ele de verdade logo em seguida.
    var accountsProvider: () -> [AccountSession]
    /// Injetável só pros testes não esperarem o intervalo de verdade. `nil` usa o mesmo intervalo
    /// do `poster` compartilhado (o normal, já que os dois precisam respeitar o mesmo bloqueio).
    private let interval: TimeInterval

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
        return poster.statuses[item.product.id] ?? .pending
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

    /// Não cancela uma chamada de rede já em voo (deixa terminar sozinha) — só tira o item da
    /// lista e da vez dele na fila.
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
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
        while let item = items.first(where: { status(for: $0) == .pending }) {
            guard let source = accountsProvider().first(where: { $0.id == item.sourceAccountID }),
                  let destination = accountsProvider().first(where: { $0.id == item.destinationAccountID }) else {
                failureOverrides[item.id] = "conta não está mais logada"
                continue
            }
            // Uma postagem avulsa pode ter acabado de deixar o poster compartilhado em cooldown —
            // espera passar antes de tentar, senão `poster.post` vira no-op.
            while poster.isInCooldown {
                try? await Task.sleep(for: .seconds(1))
            }
            await postAndTrack(item: item, source: source, destination: destination)
            if items.contains(where: { status(for: $0) == .pending }) {
                try? await Task.sleep(for: .seconds(interval))
            }
        }
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
}
