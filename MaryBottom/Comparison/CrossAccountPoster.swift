import Foundation
import Observation

/// Publica na conta B um produto que só existe na conta A (ou vice-versa) — lê o template pela
/// sessão de origem e cria pela sessão de destino, cada uma com seu próprio CSRF token. Igual ao
/// repost do `MegaphoneRunner`, mas cruzando duas contas em vez de duplicar dentro da mesma.
@MainActor
@Observable
final class CrossAccountPoster {
    /// Por produto + conta de destino, não só por produto — o mesmo produto pode estar sendo (ou
    /// já ter sido) postado em duas contas de destino diferentes ao mesmo tempo (ex.: comparado
    /// contra a conta B e, antes disso terminar, contra a conta C também); chavear só por
    /// `product.id` faria a segunda postagem reaproveitar o status da primeira sem nunca rodar de
    /// verdade. Ver `PostTarget`.
    private(set) var statuses: [PostTarget: MegaphoneStatus] = [:]
    /// Link do anúncio novo, quando a resposta da criação trouxer como identificar ele.
    private(set) var postedProductURLs: [PostTarget: URL] = [:]
    /// Diagnóstico completo da última falha ao postar cada produto — só em memória. Ver
    /// `MegaphoneRunner.failureDetails`, mesmo raciocínio.
    private(set) var failureDetails: [PostTarget: MegaphoneFailureDetail] = [:]

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
        let target = PostTarget(productID: product.id, destinationAccountID: destination.id)
        guard !isInCooldown else { return }
        guard statuses[target] != .megaphoning, statuses[target] != .succeeded else { return }
        statuses[target] = .megaphoning
        Task { [weak self] in
            await self?.run(product: product, from: source, to: destination, target: target)
        }
    }

    private func run(
        product: EnjoeiProduct,
        from source: AccountSession,
        to destination: AccountSession,
        target: PostTarget
    ) async {
        do {
            let template = try await source.client.productTemplate(productID: product.id)
            let token = try await destination.client.csrfToken()
            let response = try await createProduct(
                ProductCreateRequest(template: template),
                token: token,
                client: destination.client
            )
            if let path = response.path {
                postedProductURLs[target] = EnjoeiAPI.productURL(path: path)
            }
            statuses[target] = .succeeded
            cooldownUntil = Date().addingTimeInterval(cooldownDuration)
        } catch {
            statuses[target] = .failed(error.localizedDescription)
            failureDetails[target] = MegaphoneFailureDetail(action: .post, error: error)
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
