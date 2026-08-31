import Foundation
import Observation

/// Conduz a comparação entre duas contas: garante que as duas tenham a lista de produtos
/// carregada (buscando sozinho quando falta) e roda o casamento por similaridade.
@MainActor
@Observable
final class AccountComparisonLoader {
    enum Phase: Equatable, Sendable {
        case idle
        case loadingProducts
        case finished(AccountComparisonResult)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    func compare(accountA: AccountSession, accountB: AccountSession) {
        guard task == nil else { return }
        phase = .loadingProducts
        task = Task { [weak self] in
            await self?.run(accountA: accountA, accountB: accountB)
            self?.task = nil
        }
    }

    /// Serve aos testes; a tela só observa `phase`.
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(accountA: AccountSession, accountB: AccountSession) async {
        // Reaproveita a lista já carregada (ou persistida em disco) de cada conta — só busca de
        // novo quando realmente não tem nada ainda, igual ao que a própria tela de detalhe já faz.
        if accountA.runner.items.isEmpty {
            accountA.runner.load(sellerID: accountA.user.id)
            await accountA.runner.waitUntilFinished()
        }
        if accountB.runner.items.isEmpty {
            accountB.runner.load(sellerID: accountB.user.id)
            await accountB.runner.waitUntilFinished()
        }

        let productsA = accountA.runner.items.map(\.product)
        let productsB = accountB.runner.items.map(\.product)
        // O(N×M) pares — tira do MainActor pra não travar a tela numa loja grande.
        let result = await Task.detached {
            AccountProductMatcher.compare(productsA: productsA, productsB: productsB)
        }.value
        phase = .finished(result)
    }
}
