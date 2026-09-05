import Foundation

/// Quem sabe guardar a lista de produtos que um megafone já carregou, entre uma abertura do app e
/// outra — pra não buscar a loja inteira de novo toda vez, só quando o usuário força o recarregar.
/// Uma instância cuida de uma conta só. Protocolo para os testes não dependerem de disco de verdade.
@MainActor
protocol MegaphoneItemsPersisting {
    func loadItems() -> [MegaphoneItem]
    func saveItems(_ items: [MegaphoneItem])
    /// Busca por título direto na persistência (no SwiftData, via `#Predicate` + `fetchLimit` — ver
    /// `SwiftDataMegaphoneItemsPersistence`), devolvendo só os ids que batem — não o `MegaphoneItem`
    /// reconstruído por inteiro, porque o `status`/`exposição` salvos aqui nunca refletem uma
    /// megafonagem em andamento (só existe ao vivo em `MegaphoneRunner.items`). Quem chama deve
    /// cruzar esses ids com a lista ao vivo pra remontar o item de verdade — ver
    /// `MegaphoneRunner.searchProductIDs(matching:)`/`AccountPublishedTabView.recomputeFilteredItems`.
    /// `query` vazia devolve os primeiros `limit` ids sem filtrar.
    func searchProductIDs(matching query: String, limit: Int) -> [Int]
    func clearItems()
    /// Grava a descrição de um produto — update pontual (não reescreve a tabela inteira como
    /// `saveItems`), pra `ProductDetailsLoader` gravar incrementalmente sem refazer o
    /// delete+reinsert de todos os outros produtos a cada um que termina. Upsert: cria o registro
    /// se esse produto ainda não estava persistido (ex.: `ProductDetailsLoader` chamado pela tela
    /// de comparação, que busca produtos frescos direto da rede, sem depender de o usuário já ter
    /// aberto a lista de publicados dessa conta antes) — `product` traz os outros campos prontos
    /// pro caso de precisar criar.
    func upsertDescription(for product: EnjoeiProduct, description: String)
}
