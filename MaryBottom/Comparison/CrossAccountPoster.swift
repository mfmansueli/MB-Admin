import Foundation
import Observation

/// Publica na conta B um produto que só existe na conta A (ou vice-versa) — lê o template pela
/// sessão de origem e cria pela sessão de destino, cada uma com seu próprio CSRF token. Igual ao
/// repost do `MegaphoneRunner`, mas cruzando duas contas em vez de duplicar dentro da mesma.
@MainActor
@Observable
final class CrossAccountPoster {
    /// Por id do produto na conta de origem — separado por produto pra postar vários da lista sem
    /// um atropelar o status do outro.
    private(set) var statuses: [Int: MegaphoneStatus] = [:]
    /// Link do anúncio novo, quando a resposta da criação trouxer como identificar ele.
    private(set) var postedProductURLs: [Int: URL] = [:]
    /// Diagnóstico completo da última falha ao postar cada produto — só em memória. Ver
    /// `MegaphoneRunner.failureDetails`, mesmo raciocínio.
    private(set) var failureDetails: [Int: MegaphoneFailureDetail] = [:]

    /// Intervalo mínimo entre uma postagem bem-sucedida e a próxima, pra não martelar a API do
    /// Enjoei — vale pra qualquer produto, não só pro que acabou de ser postado. Propriedade de
    /// instância (não `static`) pra testes poderem encurtar sem esperar 1 minuto de verdade.
    let cooldownDuration: TimeInterval
    private(set) var cooldownUntil: Date?

    var isInCooldown: Bool {
        guard let cooldownUntil else { return false }
        return Date() < cooldownUntil
    }

    init(cooldownDuration: TimeInterval = 60) {
        self.cooldownDuration = cooldownDuration
    }

    func post(product: EnjoeiProduct, from source: AccountSession, to destination: AccountSession) {
        guard !isInCooldown else { return }
        guard statuses[product.id] != .megaphoning, statuses[product.id] != .succeeded else { return }
        statuses[product.id] = .megaphoning
        Task { [weak self] in
            await self?.run(product: product, from: source, to: destination)
        }
    }

    private func run(product: EnjoeiProduct, from source: AccountSession, to destination: AccountSession) async {
        do {
            let template = try await source.client.productTemplate(productID: product.id)
            let token = try await destination.client.csrfToken()
            let response = try await createProduct(
                ProductCreateRequest(template: template),
                token: token,
                client: destination.client
            )
            if let path = response.path {
                postedProductURLs[product.id] = EnjoeiAPI.productURL(path: path)
            }
            statuses[product.id] = .succeeded
            cooldownUntil = Date().addingTimeInterval(cooldownDuration)
        } catch {
            statuses[product.id] = .failed(error.localizedDescription)
            failureDetails[product.id] = MegaphoneFailureDetail(action: .post, error: error)
        }
    }

    /// Cria o anúncio na conta de destino, renovando o token CSRF e tentando de novo quando ela
    /// recusa o token — mesmo laço do repost dentro da mesma conta.
    private func createProduct(
        _ request: ProductCreateRequest,
        token: String,
        client: EnjoeiClientProtocol
    ) async throws -> ProductCreateResponse {
        do {
            return try await client.createProduct(request, csrfToken: token)
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            return try await client.createProduct(request, csrfToken: refreshed)
        }
    }
}
