import Foundation
import Observation

/// Busca os produtos da loja e separa os que pedem decisão de desconto pra alcançar exposição
/// máxima no megafone — leitura de `GET /api/megaphones/v2`, sem executar nada.
@MainActor
@Observable
final class DiscountCandidatesLoader {
    private(set) var phase: DiscountCandidatesPhase = .idle
    private(set) var candidates: [DiscountCandidate] = []

    /// Quantos ids pedir por chamada ao endpoint de exposição — o Enjoei aceita vários de uma vez,
    /// mas evitamos mandar a loja inteira numa URL só.
    var exposureBatchSize = 80

    private let client: EnjoeiClientProtocol
    private var task: Task<Void, Never>?

    init(client: EnjoeiClientProtocol) {
        self.client = client
    }

    var isLoading: Bool { task != nil }

    func load(sellerID: Int) {
        guard task == nil else { return }
        candidates = []
        phase = .loadingProducts(loaded: 0, total: 0)
        task = Task { [weak self] in
            await self?.run(sellerID: sellerID)
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Aplica o desconto sugerido e megafona o produto. Deixa o item marcado como "rodando" até a
    /// chamada terminar; um segundo toque enquanto isso não dispara outra.
    func applyDiscount(for productID: Int) {
        guard let index = candidates.firstIndex(where: { $0.id == productID }) else { return }
        guard candidates[index].status != .megaphoning else { return }
        let newPrice = candidates[index].exposure.priceToIncreaseExposure
        candidates[index].status = .megaphoning
        Task { [weak self] in
            await self?.performApply(productID: productID, newPrice: newPrice)
        }
    }

    private func performApply(productID: Int, newPrice: Double?) async {
        do {
            let token = try await client.csrfToken()
            try await megaphone(productID: productID, newPrice: newPrice, token: token)
            setStatus(.succeeded, for: productID)
        } catch {
            setStatus(.failed(error.localizedDescription), for: productID)
        }
    }

    /// Renova o token CSRF e tenta de novo quando o servidor recusa o token em uso — mesmo laço do
    /// `MegaphoneRunner`, repetido aqui porque os dois tipos rodam em ciclos de vida separados.
    private func megaphone(productID: Int, newPrice: Double?, token: String) async throws {
        do {
            try await client.megaphone(productID: productID, csrfToken: token, newPrice: newPrice)
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.megaphone(productID: productID, csrfToken: refreshed, newPrice: newPrice)
        }
    }

    /// Procura de novo o índice em vez de guardar o de antes do `await`: um `load()` disparado no
    /// meio do caminho recria `candidates` do zero.
    private func setStatus(_ status: MegaphoneStatus, for productID: Int) {
        guard let index = candidates.firstIndex(where: { $0.id == productID }) else { return }
        candidates[index].status = status
    }

    /// Espera o carregamento terminar. Serve aos testes; a tela só observa `phase`.
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(sellerID: Int) async {
        do {
            let products = try await loadAllProducts(sellerID: sellerID)
            phase = .checkingExposure(checked: 0, total: products.count)
            let exposures = try await loadExposures(productIDs: products.map(\.id))

            candidates = products.compactMap { product in
                guard let exposure = exposures[product.id], exposure.kind.requiresDiscountDecision else {
                    return nil
                }
                return DiscountCandidate(product: product, exposure: exposure)
            }
            phase = .loaded
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadAllProducts(sellerID: Int) async throws -> [EnjoeiProduct] {
        var products: [EnjoeiProduct] = []
        var seenIDs: Set<Int> = []
        var cursor: String?

        while true {
            try Task.checkCancellation()
            let page = try await client.storeProductsPage(sellerID: sellerID, after: cursor)
            let newProducts = page.products.filter { seenIDs.insert($0.id).inserted }
            products.append(contentsOf: newProducts)
            phase = .loadingProducts(loaded: products.count, total: max(page.total, products.count))

            // Sem cursor novo, sem produto inédito, ou cursor repetido: acabou a loja.
            guard let endCursor = page.endCursor, !newProducts.isEmpty, endCursor != cursor else {
                return products
            }
            cursor = endCursor
        }
    }

    private func loadExposures(productIDs: [Int]) async throws -> [Int: MegaphoneExposure] {
        var exposuresByProductID: [Int: MegaphoneExposure] = [:]
        var checked = 0

        for batch in chunks(of: productIDs, size: exposureBatchSize) {
            try Task.checkCancellation()
            let exposures = try await client.megaphoneExposures(productIDs: batch)
            for exposure in exposures { exposuresByProductID[exposure.productID] = exposure }
            checked += batch.count
            phase = .checkingExposure(checked: checked, total: productIDs.count)
        }
        return exposuresByProductID
    }

    private func chunks(of ids: [Int], size: Int) -> [[Int]] {
        stride(from: 0, to: ids.count, by: size).map {
            Array(ids[$0..<min($0 + size, ids.count)])
        }
    }
}
