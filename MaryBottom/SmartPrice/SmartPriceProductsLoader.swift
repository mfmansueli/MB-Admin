import Foundation
import Observation

/// Busca todas as páginas de produtos SEM preço esperto (`tab=false`) da própria loja, uma vez,
/// guardando o resultado em disco pra não buscar tudo de novo a próxima vez que a aba "sem preço
/// esperto" for aberta — molde de `InactiveProductsLoader`, com paginação de verdade
/// (`pagination.total_pages`) em vez do "maior /page/N visto" que a raspagem de inativos precisa
/// inferir do HTML. Ativar produtos (avulso ou em massa) vive em
/// `SmartPriceProductsLoader+Activation.swift`.
@MainActor
@Observable
final class SmartPriceProductsLoader {
    enum Phase: Equatable, Sendable {
        case idle
        case loadingPage(Int, of: Int)
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [SmartPriceProduct] = []
    private var task: Task<Void, Never>?
    /// `var`, não `let`: testes zeram, igual `InactiveProductsLoader.delayBetweenPages` — não faz
    /// sentido esperar de verdade entre páginas da mesma conta num teste.
    var delayBetweenPages: Duration = .milliseconds(300)

    /// Situação de ativar o preço esperto de cada produto, por id — separado de `phase` (que é só
    /// do carregamento da listagem em si). Métodos em `SmartPriceProductsLoader+Activation.swift`.
    internal(set) var activationStatuses: [Int: MegaphoneStatus] = [:]
    /// Intervalo entre uma ativação e a próxima, pra não martelar a API — mesmo valor padrão do
    /// megafone (`MegaphoneRunner.delayBetweenProducts`). `var` pros testes zerarem.
    var delayBetweenActivations: Duration = .milliseconds(900)
    // Sem `private` nas duas linhas abaixo: usadas pelos métodos movidos pra
    // `SmartPriceProductsLoader+Activation.swift` (mesmo raciocínio do `internal(set)` acima —
    // `private` em Swift vale por arquivo, não por tipo).
    var activationQueue: [Int] = []
    var isProcessingActivations = false

    // Também sem `private` — usado pelos métodos de ativação movidos pro arquivo de extensão.
    let client: EnjoeiClientProtocol
    private let accountID: EnjoeiAccountID
    private let itemsPersistence: SmartPriceProductsPersisting

    init(
        client: EnjoeiClientProtocol,
        accountID: EnjoeiAccountID = UUID(),
        itemsPersistence: SmartPriceProductsPersisting = InMemorySmartPriceProductsPersistence()
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
            var totalPages = 1
            var collected: [SmartPriceProduct] = []
            repeat {
                phase = .loadingPage(page, of: totalPages)
                let result = try await client.smartPriceProductsPage(page: page, tab: false)
                collected += result.products
                totalPages = result.totalPages
                items = collected
                page += 1
                if page <= totalPages, delayBetweenPages > .zero {
                    try await Task.sleep(for: delayBetweenPages)
                }
            } while page <= totalPages
            itemsPersistence.saveItems(items, accountID: accountID)
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
