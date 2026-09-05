import Foundation
import Observation

/// Limita quantas contas megafonam de verdade (a parte pesada — rede + JS via `WKWebView`) ao mesmo
/// tempo. Cada conta tem sua própria `WKWebView` sempre carregada (ver `AccountSession`) — deixar
/// várias fazendo trabalho pesado ao mesmo tempo sobrecarrega o aparelho (vários processos
/// `WebContent`/GPU do WebKit ativos juntos). Compartilhada entre todas as contas — mesmo raciocínio
/// de `PostQueue`, só que aqui não processa item por item, só decide QUANDO cada
/// `MegaphoneRunner.start()` pode de fato começar a rodar.
///
/// Não mexe no ciclo de vida da `WKWebView` (criar/destruir) de propósito — essa área já teve um
/// crash real do próprio WebKit (ver `AccountsStore.swift`), então esta fila só governa quando o
/// trabalho de rede acontece, nunca a `WKWebView` em si.
///
/// `baseLimit` (o teto normal, escolhido pelo usuário) é fixo, mas um aviso de memória real do
/// sistema pode empurrar um teto temporário por cima dele (ver `applyMemoryPressureCap(_:)`,
/// ligado em `AccountsStore` a um `MemoryPressureObserving`) — rede de segurança automática para o
/// cenário que motivou `baseLimit = .max`: várias lojas grandes megafonando juntas.
@MainActor
@Observable
final class MegaphoneQueue {
    /// Quantas contas podem megafonar de verdade ao mesmo tempo, em condição normal — decisão do
    /// usuário (ver `AccountsStore.megaphoneQueue`). Nunca mexida por pressão de memória; só o teto
    /// abaixo reage a isso.
    private let baseLimit: Int
    /// Teto temporário imposto por um aviso de memória real do sistema (ver
    /// `applyMemoryPressureCap(_:)`) — `nil` fora de pressão. Só reduz, nunca aumenta `baseLimit`.
    private var pressureCap: Int?
    private var effectiveLimit: Int { min(baseLimit, pressureCap ?? .max) }
    private var activeRunnerIDs: Set<ObjectIdentifier> = []
    private var waitingOrder: [ObjectIdentifier] = []
    private var waitersByRunnerID: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    // `nonisolated`: usado como expressão de argumento padrão em `MegaphoneRunner.init`/
    // `AccountSession.init`, avaliada fora do MainActor — sem isso, o compilador recusa construir
    // o valor padrão inline.
    nonisolated init(concurrencyLimit: Int = 1) {
        self.baseLimit = concurrencyLimit
    }

    /// `true` enquanto essa conta já pediu pra megafonar mas ainda está esperando a vez — pra a
    /// tela mostrar "na fila" em vez de qualquer outro estado.
    func isWaiting(_ runner: MegaphoneRunner) -> Bool {
        waitingOrder.contains(ObjectIdentifier(runner))
    }

    /// Suspende até essa conta ter permissão pra megafonar de verdade — ou até ser cancelada
    /// enquanto ainda estava esperando. Quem chama sempre deve chamar `release(_:)` depois, mesmo
    /// se cancelada (é seguro: `release` só mexe em algo se essa conta realmente tinha a vez).
    func acquire(_ runner: MegaphoneRunner) async {
        let id = ObjectIdentifier(runner)
        guard activeRunnerIDs.count >= effectiveLimit else {
            activeRunnerIDs.insert(id)
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waitingOrder.append(id)
                waitersByRunnerID[id] = continuation
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancelWaiting(id: id) }
        }
        // Chega aqui tanto por ter sido promovida (chegou a vez) quanto por ter sido cancelada
        // enquanto esperava — o `defer { release(...) }` de quem chamou cuida de liberar de novo
        // sem problema nos dois casos (ver comentário em `release`).
        activeRunnerIDs.insert(id)
    }

    /// Libera a vez dessa conta — chamar sempre que ela parar de megafonar de verdade (terminou,
    /// cancelou, falhou) ou de esperar na fila, pra a próxima poder começar. Seguro chamar mesmo
    /// que essa conta nunca tenha chegado a ocupar uma vaga.
    func release(_ runner: MegaphoneRunner) {
        let id = ObjectIdentifier(runner)
        guard activeRunnerIDs.remove(id) != nil else { return }
        // Ninguém mais rodando: esquece o aviso de pressão sozinho, sem precisar de um "acabou"
        // explícito do sistema — se a pressão continuar de verdade, um novo aviso chega assim que
        // a próxima conta ocupar uma vaga e voltar a pesar de verdade.
        if activeRunnerIDs.isEmpty {
            pressureCap = nil
        }
        promoteNextWaiter()
    }

    /// Chamado por um observador de aviso de memória (ver `MemoryPressureObserving`) — nunca aborta
    /// quem já está rodando (um lote de `megaphoneAll` em andamento sempre termina), só limita
    /// quantas contas NOVAS a fila deixa começar enquanto o aviso estiver de pé. `nil` remove o
    /// teto na hora.
    func applyMemoryPressureCap(_ cap: Int?) {
        pressureCap = cap
    }

    private func cancelWaiting(id: ObjectIdentifier) {
        guard let index = waitingOrder.firstIndex(of: id) else { return }
        waitingOrder.remove(at: index)
        waitersByRunnerID.removeValue(forKey: id)?.resume()
    }

    /// Só promove enquanto ainda houver vaga sob o teto atual — com `pressureCap` reduzindo
    /// `effectiveLimit` no meio do caminho, uma vaga liberada não significa mais, por si só, que dá
    /// pra admitir mais alguém.
    private func promoteNextWaiter() {
        guard activeRunnerIDs.count < effectiveLimit, !waitingOrder.isEmpty else { return }
        let nextID = waitingOrder.removeFirst()
        waitersByRunnerID.removeValue(forKey: nextID)?.resume()
    }
}
