import Foundation

/// Ativa o preço esperto de um ou vários produtos — mesma rota por trás tanto do botão avulso do
/// menu "..." de uma linha quanto da ação em massa da seleção múltipla. O endpoint nativo de
/// "ativar em todos" (o botão da própria tela do Enjoei) não foi capturado (ver documento da API,
/// seção "Lacunas") — por isso um loop por produto aqui, com intervalo entre um e o próximo, em vez
/// de chamar um endpoint de lote.
extension SmartPriceProductsLoader {
    /// Enfileira os ids pedidos pra ativar, um de cada vez — chamável tanto com um id só (linha
    /// avulsa) quanto com vários (seleção múltipla); uma chamada nova enquanto a fila já está
    /// correndo só acrescenta no fim, sem reiniciar o que já estava em andamento. Ids já em
    /// andamento ou já concluídos com sucesso são ignorados, pra um segundo toque não duplicar a
    /// chamada.
    func activate(productIDs: [Int]) {
        let ids = productIDs.filter {
            activationStatuses[$0] != .succeeded
                && activationStatuses[$0] != .megaphoning
                && !activationQueue.contains($0)
        }
        guard !ids.isEmpty else { return }
        for id in ids { activationStatuses[id] = .pending }
        activationQueue.append(contentsOf: ids)
        guard !isProcessingActivations else { return }
        isProcessingActivations = true
        Task { [weak self] in
            await self?.drainActivationQueue()
        }
    }

    private func drainActivationQueue() async {
        var token = (try? await client.csrfToken()) ?? ""
        while !activationQueue.isEmpty {
            let productID = activationQueue.removeFirst()
            activationStatuses[productID] = .megaphoning
            do {
                token = try await activateOne(productID: productID, token: token)
                activationStatuses[productID] = .succeeded
            } catch {
                activationStatuses[productID] = .failed(error.localizedDescription)
            }
            if !activationQueue.isEmpty, delayBetweenActivations > .zero {
                try? await Task.sleep(for: delayBetweenActivations)
            }
        }
        isProcessingActivations = false
    }

    /// Ativa um produto, renovando o token CSRF e tentando de novo quando o servidor recusa o token
    /// — mesmo raciocínio de `MegaphoneRunner.megaphone`, ele gira junto com a sessão.
    private func activateOne(productID: Int, token: String) async throws -> String {
        do {
            try await client.setSmartPrice(productID: productID, activate: true, csrfToken: token)
            return token
        } catch let error as EnjoeiError where error.isCSRFRejection {
            let refreshed = try await client.csrfToken()
            try await client.setSmartPrice(productID: productID, activate: true, csrfToken: refreshed)
            return refreshed
        }
    }
}
