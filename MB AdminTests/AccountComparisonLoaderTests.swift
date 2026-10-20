import Foundation
import Testing
@testable import MB_Admin

@Suite("carregador da comparação entre duas contas")
struct AccountComparisonLoaderTests {
    private func makeAccount(id: EnjoeiAccountID = EnjoeiAccountID(), client: StubEnjoeiClient) -> AccountSession {
        AccountSession(
            id: id,
            user: .stub,
            dependencies: AccountDependencies(client: client, sessionClearer: FakeSessionClearer(), webView: nil)
        )
    }

    @Test("mesmo com o runner já carregado, comparar busca de novo — não reaproveita a lista, que pode estar desatualizada")
    func buscaDeNovoMesmoJaCarregado() async {
        let title = "colar curto prata 925 zircônia branca"
        let clientA = StubEnjoeiClient(pages: [
            // Primeira página: consumida pelo carregamento manual do runner abaixo, simulando um
            // estado velho na conta (produto id 1).
            StoreProductsPage(products: [EnjoeiFixtures.product(id: 1, title: title)], total: 1, endCursor: nil),
            // Segunda página: o que o servidor devolve agora, com um produto novo (id 99) — como se
            // tivesse sido ativado/editado depois do carregamento manual.
            StoreProductsPage(products: [EnjoeiFixtures.product(id: 99, title: title)], total: 1, endCursor: nil)
        ])
        let accountA = makeAccount(client: clientA)
        accountA.runner.load(sellerID: 1)
        await accountA.runner.waitUntilFinished()
        #expect(accountA.runner.items.map(\.id) == [1])

        let clientB = StubEnjoeiClient(pages: [
            StoreProductsPage(products: [EnjoeiFixtures.product(id: 2, title: title)], total: 1, endCursor: nil)
        ])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()

        // "comparar" é um pedido explícito de estado atual — precisa buscar de novo, não reaproveitar
        // `runner.items`, senão um produto ativado/editado depois do carregamento anterior nunca
        // apareceria na comparação.
        #expect(await clientA.requestedCursors.count == 2)

        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
        // Casou com o produto 99 (buscado agora pela comparação), não o 1 (que ficou só na lista
        // velha do runner).
        #expect(result.matches.map(\.productA.id) == [99])
        #expect(result.matches.map(\.productB.id) == [2])
    }

    @Test("comparar não consulta exposição — isso é coisa do megafone e deixaria a comparação lenta à toa")
    func naoConsultaExposicao() async {
        let clientA = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [2], endCursor: nil)])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()

        #expect(await clientA.requestedExposureBatches.isEmpty)
        #expect(await clientB.requestedExposureBatches.isEmpty)
    }

    @Test("conta sem produtos carregados busca sozinha antes de comparar")
    func buscaSozinhoQuandoVazio() async {
        let clientA = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1], endCursor: nil)
        ])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [2], endCursor: nil)
        ])
        let accountB = makeAccount(client: clientB)

        #expect(accountA.runner.items.isEmpty)
        #expect(accountB.runner.items.isEmpty)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()

        #expect(await clientA.requestedCursors.count == 1)
        #expect(await clientB.requestedCursors.count == 1)
        guard case .finished = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
    }

    @Test("cada comparação tem um id diferente, mesmo comparando o mesmo par de contas de novo")
    func cadaComparacaoTemIDDiferente() async {
        let clientA = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [1], endCursor: nil),
            EnjoeiFixtures.page(ids: [1], endCursor: nil)
        ])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [
            EnjoeiFixtures.page(ids: [2], endCursor: nil),
            EnjoeiFixtures.page(ids: [2], endCursor: nil)
        ])
        let accountB = makeAccount(client: clientB)
        let loader = AccountComparisonLoader()

        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()
        guard case .finished(let firstResult) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }

        // Comparar de novo, mesmo par de contas — a tela usa esse id (`.id(result.id)`) pra saber
        // quando zerar busca/filtro/seleção de `ComparisonResultView`; sem um id novo aqui, uma
        // seleção feita antes de comparar de novo sobreviveria pro resultado novo.
        loader.compare(accountA: accountA, accountB: accountB)
        await loader.waitUntilFinished()
        guard case .finished(let secondResult) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }

        #expect(firstResult.id != secondResult.id)
    }

    @Test("comparação completa busca a descrição de cada produto das duas contas antes de comparar")
    func comparacaoCompletaBuscaDescricaoDasDuasContas() async {
        let clientA = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)],
            templatesByProductID: [1: EnjoeiFixtures.productTemplate(description: "colar curto prata 925 zircônia branca")]
        )
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [2], endCursor: nil)],
            templatesByProductID: [2: EnjoeiFixtures.productTemplate(description: "colar curto prata 925 zircônia branca")]
        )
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, fullComparison: true)
        await loader.waitUntilFinished()

        #expect(await clientA.requestedTemplateIDs == [1])
        #expect(await clientB.requestedTemplateIDs == [2])
        // Guardou no banco local das duas contas, não só usou pra comparar na hora.
        #expect(accountA.productDetailsLoader.detailedCount == 1)
        #expect(accountB.productDetailsLoader.detailedCount == 1)

        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
        // Títulos sozinhos (fixture padrão "brinco prata 925", ids diferentes) não bateriam o
        // threshold — casaram porque a descrição buscada é idêntica dos dois lados.
        #expect(result.matches.count == 1)
    }

    /// Regressão: um produto pulado nesta rodada (já tinha descrição salva de uma comparação
    /// anterior, com QUALQUER conta) não pode comparar só por título enquanto o outro lado (buscado
    /// agora de verdade) compara por título+descrição — isso derrubava o score de pares idênticos
    /// pra ~50% em vez de 100%.
    @Test("produto já com descrição salva de uma comparação anterior ainda casa 100%, não fica pra trás")
    func produtoJaComDescricaoAntigaAindaCasaCemPorCento() async {
        let title = "bracelete feminino aro amassado - banho de ouro 18k"
        let description = "bracelete aro amassado com banho de ouro. código:177 18cm de curvatura interna peso: 9gr"
        let productA = EnjoeiFixtures.product(id: 1, title: title)
        let productB = EnjoeiFixtures.product(id: 2, title: title)

        // Conta A já teve o produto 1 buscado numa comparação completa anterior, com uma terceira
        // conta — ele já tem descrição salva, então `fetchAll` vai pulá-lo nesta rodada.
        let clientA = StubEnjoeiClient(
            pages: [StoreProductsPage(products: [productA], total: 1, endCursor: nil)],
            templatesByProductID: [1: EnjoeiFixtures.productTemplate(description: description)]
        )
        let accountA = makeAccount(client: clientA)
        accountA.productDetailsLoader.fetchAll(products: [productA])
        await accountA.productDetailsLoader.waitUntilFinished()
        #expect(await clientA.requestedTemplateIDs == [1])

        // Conta B nunca buscou detalhe nenhum — vai buscar de verdade nesta comparação.
        let clientB = StubEnjoeiClient(
            pages: [StoreProductsPage(products: [productB], total: 1, endCursor: nil)],
            templatesByProductID: [2: EnjoeiFixtures.productTemplate(description: description)]
        )
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, fullComparison: true)
        await loader.waitUntilFinished()

        // O produto 1 não devia ser buscado de novo (já tinha descrição) — só o 2.
        #expect(await clientA.requestedTemplateIDs == [1])
        #expect(await clientB.requestedTemplateIDs == [2])

        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
        #expect(result.matches.count == 1)
        #expect(result.matches.first?.similarity == 1)
    }

    @Test("sem comparação completa, não busca template nenhum — comportamento de sempre")
    func semComparacaoCompletaNaoBuscaTemplate() async {
        let clientA = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [2], endCursor: nil)])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, fullComparison: false)
        await loader.waitUntilFinished()

        #expect(await clientA.requestedTemplateIDs.isEmpty)
        #expect(await clientB.requestedTemplateIDs.isEmpty)
    }

    /// Mesmo sem o toggle "comparação completa" ligado nesta chamada, uma descrição já salva
    /// localmente (de uma comparação completa anterior, com qualquer conta) deve valer — o toggle
    /// só controla se busca coisa NOVA pela rede, não se usa o que já está disponível.
    @Test("sem comparação completa, ainda usa descrição já salva localmente, sem buscar nada novo")
    func semComparacaoCompletaAindaUsaDescricaoJaSalva() async {
        let title = "peça exclusiva prata"
        let description = "colar curto prata 925 zircônia branca clássico elegante"
        let productA = EnjoeiFixtures.product(id: 1, title: title)
        let productB = EnjoeiFixtures.product(id: 2, title: "joia linda presente")

        let clientA = StubEnjoeiClient(
            pages: [StoreProductsPage(products: [productA], total: 1, endCursor: nil)],
            templatesByProductID: [1: EnjoeiFixtures.productTemplate(description: description)]
        )
        let accountA = makeAccount(client: clientA)
        // Descrição já salva de antes — simula uma comparação completa anterior com outra conta.
        accountA.productDetailsLoader.fetchAll(products: [productA])
        await accountA.productDetailsLoader.waitUntilFinished()

        let clientB = StubEnjoeiClient(
            pages: [StoreProductsPage(products: [productB], total: 1, endCursor: nil)],
            templatesByProductID: [2: EnjoeiFixtures.productTemplate(description: description)]
        )
        let accountB = makeAccount(client: clientB)
        accountB.productDetailsLoader.fetchAll(products: [productB])
        await accountB.productDetailsLoader.waitUntilFinished()

        // Reseta a contagem de chamadas antes de comparar, pra confirmar que a comparação em si
        // (sem o toggle) não pede nada novo.
        #expect(await clientA.requestedTemplateIDs == [1])
        #expect(await clientB.requestedTemplateIDs == [2])

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB, fullComparison: false)
        await loader.waitUntilFinished()

        // Nenhuma chamada nova — só usou o que já estava salvo.
        #expect(await clientA.requestedTemplateIDs == [1])
        #expect(await clientB.requestedTemplateIDs == [2])

        guard case .finished(let result) = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
        // Títulos sozinhos não bateriam o threshold — casou porque a descrição já salva entrou na
        // comparação mesmo com o toggle desligado.
        #expect(result.matches.count == 1)
    }

    @Test("phase passa por loadingProducts antes de finished")
    func phasePassaPorLoadingProducts() async {
        let clientA = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)])
        let accountA = makeAccount(client: clientA)
        let clientB = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [2], endCursor: nil)])
        let accountB = makeAccount(client: clientB)

        let loader = AccountComparisonLoader()
        loader.compare(accountA: accountA, accountB: accountB)

        // O phase muda pra loadingProducts na hora, antes de qualquer await — sincronamente.
        #expect(loader.phase == .loadingProducts(loaded: 0, total: 0))

        await loader.waitUntilFinished()

        guard case .finished = loader.phase else {
            Issue.record("esperava .finished, veio \(loader.phase)")
            return
        }
    }
}
