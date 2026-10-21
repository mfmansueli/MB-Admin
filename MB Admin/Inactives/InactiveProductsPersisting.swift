import Foundation

/// Quem sabe guardar a lista de produtos inativos entre uma abertura do app e outra — pra não
/// buscar a loja inteira de novo toda vez, só quando a aba "inativos" é aberta sem nada carregado
/// ainda. Uma instância cuida de uma conta só (ver `SwiftDataInactiveProductsPersistence`, que abre
/// o `ModelContainer` daquela conta já no `init`). Protocolo para os testes não dependerem de disco
/// de verdade.
@MainActor
protocol InactiveProductsPersisting {
    func loadItems() -> [InactiveProduct]
    func saveItems(_ items: [InactiveProduct])
    /// Grava uma página assim que ela chega da rede, sem apagar o que já tinha sido gravado antes
    /// dela — `offset` é a posição de `items[0]` na lista completa (pra `sortIndex` continuar
    /// crescendo entre uma página e a próxima, não reiniciar do zero a cada chamada). Quem chama
    /// deve ter limpado a conta com `clearItems` antes da primeira página de um carregamento novo.
    func appendPage(_ items: [InactiveProduct], startingAt offset: Int)
    /// Busca por título direto na persistência (no SwiftData, via `#Predicate` + `fetchLimit` — ver
    /// `SwiftDataInactiveProductsPersistence`), em vez de decodificar tudo e filtrar em memória.
    /// `query` vazia devolve os primeiros `limit` itens sem filtrar.
    func search(matching query: String, limit: Int) -> [InactiveProduct]
    /// Tira um produto só, sem mexer na ordem (`sortIndex`) dos outros — sem efeito se ele não
    /// estiver guardado (ex.: um produto publicado, não inativo, apagado pela fila).
    func removeItem(productID: Int)
    func clearItems()
}
