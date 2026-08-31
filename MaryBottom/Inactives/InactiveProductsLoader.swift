import Foundation
import Observation

/// Busca todas as páginas de produtos inativos da própria loja, uma vez, guardando o resultado em
/// disco pra não buscar tudo de novo a próxima vez que a aba "inativos" for aberta — molde
/// simplificado do `MegaphoneRunner` (sem rodadas nem pausa, só um carregamento).
@MainActor
@Observable
final class InactiveProductsLoader {
    enum Phase: Equatable, Sendable {
        case idle
        case loadingPage(Int, of: Int)
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [InactiveProduct] = []
    private var task: Task<Void, Never>?
    /// `var`, não `let`: testes zeram, igual `MegaphoneRunner.delayBetweenProducts` — não faz
    /// sentido esperar de verdade entre páginas da mesma conta num teste.
    var delayBetweenPages: Duration = .milliseconds(300)

    private let client: EnjoeiClientProtocol
    private let accountID: EnjoeiAccountID
    private let itemsPersistence: InactiveProductsPersisting

    init(
        client: EnjoeiClientProtocol,
        accountID: EnjoeiAccountID = UUID(),
        itemsPersistence: InactiveProductsPersisting = InMemoryInactiveProductsPersistence()
    ) {
        self.client = client
        self.accountID = accountID
        self.itemsPersistence = itemsPersistence
        items = itemsPersistence.loadItems(accountID: accountID)
    }

    func load() {
        guard task == nil else { return }
        phase = .loadingPage(1, of: 1)
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    private func run() async {
        do {
            var page = 1
            var maxPage = 1
            var collected: [InactiveProduct] = []
            repeat {
                phase = .loadingPage(page, of: maxPage)
                let result = try await client.inactiveProductsPage(page: page)
                collected += result.products
                maxPage = result.maxPage
                items = collected
                page += 1
                if page <= maxPage, delayBetweenPages > .zero {
                    try await Task.sleep(for: delayBetweenPages)
                }
            } while page <= maxPage
            itemsPersistence.saveItems(items, accountID: accountID)
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
