import Foundation
import Observation

/// Busca a descrição de cada produto (`EnjoeiClientProtocol.productTemplate` — a mesma rota que o
/// repost já usa pra ler o anúncio inteiro), um de cada vez, e grava tanto na lista ao vivo
/// (`onDescriptionFetched`) quanto no disco (`upsertDescription`). Não existe rota em lote pra
/// isso — ao contrário da paginação de listagem ou da checagem de exposição, aqui é sempre uma
/// chamada por produto, então uma loja grande (milhares de produtos) pode levar bastante tempo.
/// Pula produtos que já têm descrição salva localmente, então tocar de novo depois de uma busca
/// interrompida só continua de onde parou, em vez de perguntar tudo de novo. Um por
/// `AccountSession` (ver `productDetailsLoader`); a tela de comparação dispara o de duas contas ao
/// mesmo tempo.
@MainActor
@Observable
final class ProductDetailsLoader {
    enum Phase: Equatable, Sendable {
        case idle
        case fetching(fetched: Int, total: Int)
        case finished
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?
    /// Intervalo entre um produto e o próximo, pra não martelar o Enjoei — mesmo raciocínio de
    /// `MegaphoneRunner.delayBetweenProducts`. `var` pros testes zerarem.
    var delayBetweenProducts: Duration = .milliseconds(300)

    /// Chamado a cada produto que responde com sucesso — quem cria este loader (`AccountSession`)
    /// liga isso na lista ao vivo do megafone (`MegaphoneRunner.applyDescription`), já que a
    /// descrição buscada aqui não tem pra onde ir sozinha (este loader não guarda a lista de
    /// produtos, só busca e persiste).
    var onDescriptionFetched: ((_ productID: Int, _ description: String) -> Void)?

    /// Descrições buscadas na última chamada de `fetchAll` — quem dispara a busca (ex.: a tela de
    /// comparação, que trabalha com sua própria lista de produtos, sem passar por
    /// `MegaphoneRunner.items`) lê isso depois de `waitUntilFinished()` pra montar os produtos
    /// completos, sem precisar reconsultar a persistência.
    private(set) var fetchedDescriptions: [Int: String] = [:]
    /// Quantos produtos dessa conta já têm descrição salva localmente, e quantos ao todo — pra a
    /// tela de comparação mostrar antes de rodar a "comparação completa" (evita repetir a busca à
    /// toa quando já tem boa parte salva de uma vez anterior). Reflete só o que já foi persistido
    /// (`itemsPersistence`), não o catálogo real da loja — sem carregar a lista de publicados (ou
    /// comparar) pelo menos uma vez, os dois ficam em 0.
    private(set) var detailedCount = 0
    private(set) var totalCount = 0

    private let client: EnjoeiClientProtocol
    private let itemsPersistence: MegaphoneItemsPersisting
    /// Fotos (com posição), categoria, tamanho e marca de cada anúncio — o que a comparação por foto
    /// usa. Gravado junto com a descrição, a cada template que responde.
    let detailsPersistence: ProductListingDetailsPersisting
    /// Rodadas de `fetchDetails` em andamento (a comparação chama direto, sem passar por `task`).
    private var activeFetches = 0
    /// Espera antes de tentar de novo um template que falhou. `var` pros testes zerarem.
    var retryDelay: Duration = .seconds(1)

    init(
        client: EnjoeiClientProtocol,
        itemsPersistence: MegaphoneItemsPersisting,
        detailsPersistence: ProductListingDetailsPersisting? = nil
    ) {
        self.client = client
        self.itemsPersistence = itemsPersistence
        self.detailsPersistence = detailsPersistence ?? InMemoryProductListingDetailsPersistence()
        refreshDetailsStats()
    }

    var isRunning: Bool { task != nil || activeFetches > 0 }

    /// Os templates já salvos desses anúncios (de qualquer idade — quem usa decide com
    /// `ProductListingDetails.isFresh`).
    func storedDetails(for productIDs: [Int]) -> [Int: ProductListingDetails] {
        detailsPersistence.details(for: productIDs)
    }

    /// Busca o template de cada produto da lista, nessa ordem, um de cada vez no ritmo de
    /// `delayBetweenProducts` — estruturado (quem chama espera e cancela pela própria `Task`), com até
    /// `PhotoMatchingParameters.detailsFetchAttempts` tentativas por produto. Cada resposta é gravada na
    /// hora (detalhes + descrição), então uma rodada interrompida retoma de onde parou.
    func fetchDetails(for products: [EnjoeiProduct], now: () -> Date = { Date() }) async -> ProductDetailsFetchReport {
        var report = ProductDetailsFetchReport()
        guard !products.isEmpty else { return report }
        activeFetches += 1
        defer {
            activeFetches -= 1
            refreshDetailsStats()
        }
        phase = .fetching(fetched: 0, total: products.count)
        products: for (index, product) in products.enumerated() {
            if Task.isCancelled {
                report.wasCancelled = true
                break products
            }
            switch await fetchTemplate(productID: product.id) {
            case .success(let template):
                let details = ProductListingDetails(product: product, template: template, fetchedAt: now())
                detailsPersistence.upsert(details)
                itemsPersistence.upsertDescription(for: product, description: template.description)
                fetchedDescriptions[product.id] = template.description
                onDescriptionFetched?(product.id, template.description)
                report.details[product.id] = details
            case .failure(let message):
                // Falha por ter sido cancelado não é falha do anúncio — fica pra quando continuar.
                if Task.isCancelled {
                    report.wasCancelled = true
                    break products
                }
                report.failures[product.id] = message
            }
            phase = .fetching(fetched: index + 1, total: products.count)
            if index < products.count - 1, delayBetweenProducts > .zero {
                try? await Task.sleep(for: delayBetweenProducts)
            }
        }
        if Task.isCancelled { report.wasCancelled = true }
        phase = .finished
        return report
    }

    private enum TemplateOutcome {
        case success(ProductTemplate)
        case failure(String)
    }

    private func fetchTemplate(productID: Int) async -> TemplateOutcome {
        var lastMessage = "sem resposta"
        for attempt in 0..<PhotoMatchingParameters.detailsFetchAttempts {
            if Task.isCancelled { return .failure("cancelado") }
            if attempt > 0, retryDelay > .zero { try? await Task.sleep(for: retryDelay) }
            do {
                return .success(try await client.productTemplate(productID: productID))
            } catch let error as EnjoeiError {
                lastMessage = error.localizedDescription
                // Sessão caída não volta tentando de novo.
                if case .notAuthenticated = error { break }
            } catch {
                lastMessage = error.localizedDescription
            }
        }
        return .failure(lastMessage)
    }

    /// Busca a descrição de cada produto da lista que ainda não tem uma salva localmente.
    func fetchAll(products: [EnjoeiProduct]) {
        guard task == nil else { return }
        let alreadyFetched = Set(
            itemsPersistence.loadItems().filter { $0.product.description != nil }.map(\.id)
        )
        let pending = products.filter { !alreadyFetched.contains($0.id) }
        fetchedDescriptions = [:]
        guard !pending.isEmpty else {
            phase = .finished
            return
        }
        phase = .fetching(fetched: 0, total: pending.count)
        task = Task { [weak self] in
            await self?.run(products: pending)
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Descrição de cada produto (dentre os ids pedidos) que essa conta já tem salva localmente —
    /// inclui tanto o que a última chamada de `fetchAll` acabou de buscar quanto o que já estava
    /// persistido de antes (produtos pulados por já terem descrição, ver `fetchAll`). Quem
    /// enriquece produtos pra comparar deve ler daqui, não de `fetchedDescriptions` sozinho: um
    /// produto pulado nesta rodada (porque uma comparação anterior, com qualquer conta, já buscou
    /// ele) continua tendo descrição de verdade — só não passou pela rede agora.
    func knownDescriptions(for productIDs: [Int]) -> [Int: String] {
        let ids = Set(productIDs)
        var result: [Int: String] = [:]
        for item in itemsPersistence.loadItems() where ids.contains(item.id) {
            if let description = item.product.description {
                result[item.id] = description
            }
        }
        return result
    }

    /// Serve aos testes e a quem precisa esperar antes de seguir (ex.: a comparação, que só roda o
    /// casamento depois das duas contas terminarem); a tela só observa `phase`.
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(products: [EnjoeiProduct]) async {
        // Um produto falhar (removido, sem permissão, erro passageiro) não para os demais — mesmo
        // raciocínio de `MegaphoneRunner.megaphoneAll`. O próximo toque já pega só o que ainda falta.
        _ = await fetchDetails(for: products)
    }

    private func refreshDetailsStats() {
        let items = itemsPersistence.loadItems()
        totalCount = items.count
        detailedCount = items.filter { $0.product.description != nil }.count
    }
}
