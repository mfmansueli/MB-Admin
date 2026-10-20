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

    /// Só informativo pra UI (desabilita o botão "postar em X" da tela de comparação e mostra a
    /// contagem regressiva ali) — não bloqueia mais `post(...)` de verdade. Chegou a ser um gate de
    /// verdade (`guard !isInCooldown`), mas isso entrava em conflito com o intervalo configurável
    /// da fila (`PostQueue.interval`): postagens vindas da fila ficavam presas nesse piso fixo de
    /// 60s mesmo quando o usuário escolhia um intervalo menor, e a fila é quem deve mandar na
    /// pacing de tudo que ela processa — ver `PostQueue.run`. Propriedade de instância (não
    /// `static`) pra testes poderem encurtar sem esperar 1 minuto de verdade.
    let cooldownDuration: TimeInterval
    private(set) var cooldownUntil: Date?
    /// Zera `cooldownUntil` sozinho quando o bloqueio expira de verdade — sem isso, nada mudava de
    /// estado no momento exato em que o cooldown passava (`isInCooldown` só é correto no instante em
    /// que é lido), e cada linha da tela de comparação que mostra o botão "postar em X" precisava de
    /// um `TimelineView` próprio, tiquetaqueando a cada segundo só pra notar a hora certa — caro
    /// numa comparação com muitos produtos. Um `Task` só, aqui, resolve pra todo mundo que observa
    /// `isInCooldown` de uma vez.
    private var cooldownExpiryTask: Task<Void, Never>?

    var isInCooldown: Bool {
        guard let cooldownUntil else { return false }
        return Date() < cooldownUntil
    }

    init(cooldownDuration: TimeInterval = 60) {
        self.cooldownDuration = cooldownDuration
    }

    func post(product: EnjoeiProduct, from source: AccountSession, to destination: AccountSession) {
        let target = PostTarget(productID: product.id, destinationAccountID: destination.id)
        guard statuses[target] != .megaphoning, statuses[target] != .succeeded else { return }
        statuses[target] = .megaphoning
        Task { [weak self] in
            await self?.run(product: product, from: source, to: destination, target: target)
        }
    }

    /// Como `post(...)`, mas espera a postagem terminar de verdade — usado por `PostQueue`, que
    /// precisa saber quando um item acabou antes de passar pro próximo. `run(...)` já deixa
    /// `statuses[target]` resolvido (sucesso ou falha) antes de voltar, então não tem por que quem
    /// chama ficar checando o dicionário num laço só pra saber a mesma coisa que já teria de graça
    /// esperando essa função terminar.
    func postAndWait(product: EnjoeiProduct, from source: AccountSession, to destination: AccountSession) async {
        let target = PostTarget(productID: product.id, destinationAccountID: destination.id)
        guard statuses[target] != .megaphoning, statuses[target] != .succeeded else { return }
        statuses[target] = .megaphoning
        await run(product: product, from: source, to: destination, target: target)
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
            scheduleCooldownExpiry()
        } catch {
            statuses[target] = .failed(error.localizedDescription)
            failureDetails[target] = MegaphoneFailureDetail(action: .post, error: error)
        }
    }

    /// Substitui qualquer expiração agendada antes — uma postagem nova sempre estica
    /// `cooldownUntil` pra mais longe, então a tarefa antiga (que zeraria no prazo velho) tem que
    /// morrer, senão ela zera `cooldownUntil` cedo demais por cima do prazo novo.
    private func scheduleCooldownExpiry() {
        cooldownExpiryTask?.cancel()
        cooldownExpiryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(Int(cooldownDuration * 1000)))
            guard !Task.isCancelled else { return }
            cooldownUntil = nil
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
