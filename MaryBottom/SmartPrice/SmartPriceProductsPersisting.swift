import Foundation

/// Quem sabe guardar a lista de produtos sem preço esperto entre uma abertura do app e outra —
/// mesmo raciocínio de `InactiveProductsPersisting`. Protocolo para os testes não dependerem de
/// disco de verdade.
@MainActor
protocol SmartPriceProductsPersisting {
    func loadItems(accountID: EnjoeiAccountID) -> [SmartPriceProduct]
    func saveItems(_ items: [SmartPriceProduct], accountID: EnjoeiAccountID)
    /// Grava uma página assim que ela chega da rede, sem apagar o que já tinha sido gravado antes
    /// dela — mesmo raciocínio de `InactiveProductsPersisting.appendPage`. `titleResolver` resolve
    /// o título de cada produto (a API de preço esperto não devolve nome, só id/preço — ver
    /// `SmartPriceProductRecord`); `nil` grava título vazio, corrigido depois por `backfillTitles`.
    func appendPage(
        _ items: [SmartPriceProduct],
        startingAt offset: Int,
        accountID: EnjoeiAccountID,
        titleResolver: (Int) -> String?
    )
    /// Regrava o título dos registros já persistidos dessa conta usando `resolver` de novo — usado
    /// quando a fonte externa do título (a aba "publicados") atualiza depois que uma página de
    /// preço esperto já tinha sido gravada sem conseguir resolver o nome ainda.
    func backfillTitles(resolver: (Int) -> String?, accountID: EnjoeiAccountID)
    /// Busca por título direto na persistência (no SwiftData, via `#Predicate` + `fetchLimit` — ver
    /// `SwiftDataSmartPriceProductsPersistence`), em vez de decodificar tudo e filtrar em memória.
    /// `query` vazia devolve os primeiros `limit` itens sem filtrar.
    func search(matching query: String, accountID: EnjoeiAccountID, limit: Int) -> [SmartPriceProduct]
    func clearItems(accountID: EnjoeiAccountID)
}
