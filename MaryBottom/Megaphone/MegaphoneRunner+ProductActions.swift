import Foundation

/// Ações num produto específico, fora do laço de rodadas: aplicar o desconto sugerido, apagar,
/// inativar ou ativar. Extensão à parte só por organização (mesmo tipo, `MegaphoneRunner.swift`
/// ficando grande demais pra navegar).
extension MegaphoneRunner {
    /// Aplica o desconto sugerido pelo megafone num produto específico e o megafona. Funciona
    /// mesmo com a rodada automática rodando — o item marcado `.succeeded` na hora é pulado por
    /// `megaphoneAll` quando o laço chegar nele.
    func applyDiscount(for productID: Int) {
        guard let index = items.firstIndex(where: { $0.id == productID }) else { return }
        guard deleteStatuses[productID] != .succeeded else { return }
        guard inactivateStatuses[productID] != .succeeded else { return }
        // Pendente ou falhou antes (retry): tudo bem. Já rodando ou já feito: um segundo toque não
        // dispara outra chamada.
        guard items[index].status != .megaphoning, items[index].status != .succeeded else { return }
        let newPrice = items[index].exposure?.priceToIncreaseExposure
        items[index].status = .megaphoning
        Task { [weak self] in
            await self?.performApplyDiscount(productID: productID, newPrice: newPrice)
        }
    }

    func performApplyDiscount(productID: Int, newPrice: Double?) async {
        do {
            let token = try await client.csrfToken()
            _ = try await megaphone(productID: productID, newPrice: newPrice, token: token)
            setStatus(.succeeded, for: productID)
            totalSucceeded += 1
        } catch {
            setStatus(.failed(error.localizedDescription), for: productID)
            failureDetails[productID] = MegaphoneFailureDetail(action: .applyDiscount, error: error)
            totalFailed += 1
        }
    }

    /// Procura de novo o índice em vez de guardar o de antes do `await`: uma rodada nova
    /// (`start`) recria `items` do zero enquanto isso estava em andamento.
    func setStatus(_ status: MegaphoneStatus, for productID: Int) {
        guard let index = items.firstIndex(where: { $0.id == productID }) else { return }
        items[index].status = status
    }

    /// Apaga um produto de vez. Ação destrutiva e provavelmente irreversível — a confirmação fica
    /// por conta de quem chama (a tela). O item continua na lista, só marcado como excluído: tirar
    /// ele de `items` na hora derrubaria a linha (e o que estiver mostrando o resultado) da tela.
    func deleteProduct(productID: Int) {
        guard deleteStatuses[productID] != .megaphoning, deleteStatuses[productID] != .succeeded else { return }
        deleteStatuses[productID] = .megaphoning
        Task { [weak self] in
            await self?.performDelete(productID: productID)
        }
    }

    /// Mesma exclusão de `deleteProduct(productID:)`, mas esperando terminar em vez de disparar e
    /// seguir — usado pela fila de ações, que precisa saber quando pode passar pro próximo item.
    func deleteProductAndWait(productID: Int) async {
        guard deleteStatuses[productID] != .megaphoning, deleteStatuses[productID] != .succeeded else { return }
        deleteStatuses[productID] = .megaphoning
        await performDelete(productID: productID)
    }

    func performDelete(productID: Int) async {
        do {
            let token = try await client.csrfToken()
            try await deleteProduct(productID: productID, token: token)
            deleteStatuses[productID] = .succeeded
        } catch {
            deleteStatuses[productID] = .failed(error.localizedDescription)
            failureDetails[productID] = MegaphoneFailureDetail(action: .delete, error: error)
        }
    }

    /// Apaga o produto, renovando o token CSRF e tentando de novo quando o servidor recusa o token
    /// — mesmo laço do `megaphone`.
    func deleteProduct(productID: Int, token: String) async throws {
        do {
            try await client.deleteProduct(productID: productID, csrfToken: token)
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.deleteProduct(productID: productID, csrfToken: refreshed)
        }
    }

    /// Inativa um produto — sai da vitrine de publicados sem apagar de vez (ao contrário de
    /// `deleteProduct`, dá pra reverter mais tarde direto no Enjoei, com `activateProduct`). A
    /// confirmação fica por conta de quem chama. O item continua em `items`, só marcado como
    /// inativado.
    func inactivateProduct(productID: Int) {
        guard inactivateStatuses[productID] != .megaphoning, inactivateStatuses[productID] != .succeeded else { return }
        inactivateStatuses[productID] = .megaphoning
        Task { [weak self] in
            await self?.performInactivate(productID: productID)
        }
    }

    /// Mesma inativação de `inactivateProduct(productID:)`, mas esperando terminar em vez de
    /// disparar e seguir — usado pela fila de ações.
    func inactivateProductAndWait(productID: Int) async {
        guard inactivateStatuses[productID] != .megaphoning, inactivateStatuses[productID] != .succeeded else { return }
        inactivateStatuses[productID] = .megaphoning
        await performInactivate(productID: productID)
    }

    func performInactivate(productID: Int) async {
        do {
            try await sendProductStateUpdate(productID: productID, state: .disable)
            inactivateStatuses[productID] = .succeeded
        } catch {
            inactivateStatuses[productID] = .failed(error.localizedDescription)
            failureDetails[productID] = MegaphoneFailureDetail(action: .inactivate, error: error)
        }
    }

    /// Ativa de novo um produto inativado — usado a partir da aba "inativos", não da lista de
    /// publicados (por isso não mexe em `items`/`inactivateStatuses`, que são sobre a loja
    /// publicada). A confirmação fica por conta de quem chama.
    func activateProduct(productID: Int) {
        guard activateStatuses[productID] != .megaphoning, activateStatuses[productID] != .succeeded else { return }
        activateStatuses[productID] = .megaphoning
        Task { [weak self] in
            await self?.performActivate(productID: productID)
        }
    }

    /// Mesma ativação de `activateProduct(productID:)`, mas esperando terminar em vez de disparar
    /// e seguir — usado pela fila de ações.
    func activateProductAndWait(productID: Int) async {
        guard activateStatuses[productID] != .megaphoning, activateStatuses[productID] != .succeeded else { return }
        activateStatuses[productID] = .megaphoning
        await performActivate(productID: productID)
    }

    func performActivate(productID: Int) async {
        do {
            try await sendProductStateUpdate(productID: productID, state: .active)
            activateStatuses[productID] = .succeeded
        } catch {
            activateStatuses[productID] = .failed(error.localizedDescription)
            failureDetails[productID] = MegaphoneFailureDetail(action: .activate, error: error)
        }
    }

    /// Lê o produto inteiro primeiro (mesma rota de "duplicar" que o repost usa, só pra leitura —
    /// nunca cria nada aqui) e reenvia com o `product_state` pedido, porque a rota não aceita um
    /// update parcial (ver `ProductStateUpdateRequest`). Renova o token CSRF e tenta de novo
    /// quando o servidor recusa — mesmo laço do `megaphone`/`deleteProduct`.
    func sendProductStateUpdate(productID: Int, state: ProductStateUpdateRequest.ProductState) async throws {
        let template = try await client.productTemplate(productID: productID)
        let request = ProductStateUpdateRequest(template: template, state: state)
        let token = try await client.csrfToken()
        do {
            try await client.updateProductState(request, productID: productID, csrfToken: token)
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.updateProductState(request, productID: productID, csrfToken: refreshed)
        }
    }
}
