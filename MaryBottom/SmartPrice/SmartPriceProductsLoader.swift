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
    private let itemsPersistence: SmartPriceProductsPersisting

    /// Resolve o título de um produto pra indexação de busca no SwiftData — a API de preço esperto
    /// não devolve título (só id e preço), então quem sabe o nome é sempre outra fonte externa (a
    /// aba "publicados", ver `AccountSession.init`). `nil` por padrão (testes/preview não precisam
    /// disso pra funcionar; sem título resolvido ainda, o produto continua aparecendo na lista
    /// normal — só não é encontrado pela busca até `refreshPersistedTitles()` rodar de novo com o
    /// resolvedor já respondendo).
    var titleResolver: (Int) -> String? = { _ in nil }

    init(
        client: EnjoeiClientProtocol,
        itemsPersistence: SmartPriceProductsPersisting = InMemorySmartPriceProductsPersistence()
    ) {
        self.client = client
        self.itemsPersistence = itemsPersistence
        items = itemsPersistence.loadItems()
    }

    func load() {
        guard task == nil else { return }
        phase = .loadingPage(1, of: 1)
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    /// Regrava o título dos produtos já persistidos cujo nome ainda não tinha sido resolvido (ou
    /// mudou) — chamar quando `titleResolver` passar a responder mais coisas (ex.: a aba
    /// "publicados" termina de carregar depois da de preço esperto).
    func refreshPersistedTitles() {
        itemsPersistence.backfillTitles(resolver: titleResolver)
    }

    /// Busca por título direto na persistência (SwiftData em produção — ver
    /// `SwiftDataSmartPriceProductsPersistence.search(matching:)`), em vez de filtrar `items` em
    /// memória. Fachada pra `SmartPriceProductsListView` não precisar conhecer `itemsPersistence`.
    func search(matching query: String, limit: Int = 500) -> [SmartPriceProduct] {
        itemsPersistence.search(matching: query, limit: limit)
    }

    private func run() async {
        do {
            var page = 1
            var totalPages = 1
            var collected: [SmartPriceProduct] = []
            // Só limpa o que essa conta tinha persistido quando a primeira página chega de
            // verdade — mesmo raciocínio de `InactiveProductsLoader.run()`: se a rede falhar logo
            // na página 1, o cache antigo em disco continua intacto.
            var hasClearedPersistedCache = false
            repeat {
                phase = .loadingPage(page, of: totalPages)
                let result = try await client.smartPriceProductsPage(page: page, tab: false)
                if !hasClearedPersistedCache {
                    itemsPersistence.clearItems()
                    hasClearedPersistedCache = true
                }
                itemsPersistence.appendPage(result.products, startingAt: collected.count, titleResolver: titleResolver)
                collected += result.products
                totalPages = result.totalPages
                items = collected
                page += 1
                if page <= totalPages, delayBetweenPages > .zero {
                    try await Task.sleep(for: delayBetweenPages)
                }
            } while page <= totalPages
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
