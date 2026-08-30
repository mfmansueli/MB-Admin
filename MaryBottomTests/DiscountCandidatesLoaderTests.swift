import Foundation
import Testing
@testable import MaryBottom

@Suite("produtos que pedem decisão de desconto")
struct DiscountCandidatesLoaderTests {
    @Test("carrega e filtra só os que pedem desconto, preservando a ordem da loja")
    func filtraQuemPedeDesconto() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(productID: 1, kind: .maximumForFree, priceToIncreaseExposure: nil, discountLabel: nil),
                2: MegaphoneExposure(
                    productID: 2, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                ),
                3: MegaphoneExposure(
                    productID: 3, kind: .reducedForFreeOrMaximumAfterDiscount,
                    priceToIncreaseExposure: 50, discountLabel: "- 40%"
                )
            ]
        )
        let loader = DiscountCandidatesLoader(client: client)

        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        #expect(loader.phase == .loaded)
        #expect(loader.candidates.map(\.id) == [2, 3])
    }

    @Test("produto sem exposição na resposta não aparece, mas não quebra a leitura")
    func produtoSemExposicaoNaoAparece() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1, 2], endCursor: nil)],
            exposuresByProductID: [
                2: MegaphoneExposure(
                    productID: 2, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%"
                )
            ]
        )
        let loader = DiscountCandidatesLoader(client: client)

        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        #expect(loader.phase == .loaded)
        #expect(loader.candidates.map(\.id) == [2])
    }

    @Test("pede exposição em lotes do tamanho configurado")
    func pedeExposicaoEmLotes() async {
        let ids = Array(1...5)
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: ids, endCursor: nil)])
        let loader = DiscountCandidatesLoader(client: client)
        loader.exposureBatchSize = 2

        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        let batches = await client.requestedExposureBatches
        #expect(batches.count == 3)
        #expect(batches.flatMap { $0 } == ids)
    }

    @Test("erro ao consultar exposição vira falha")
    func erroViraFailed() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)],
            exposuresError: .http(status: 500, message: "o enjoei caiu")
        )
        let loader = DiscountCandidatesLoader(client: client)

        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        #expect(loader.phase == .failed("o enjoei caiu"))
    }

    @Test("cancelar no meio não trava nem derruba o app")
    func cancelarNaoTrava() async {
        let client = StubEnjoeiClient(pages: [EnjoeiFixtures.page(ids: [1, 2, 3], endCursor: nil)])
        let loader = DiscountCandidatesLoader(client: client)

        loader.load(sellerID: 1)
        loader.cancel()
        await loader.waitUntilFinished()

        #expect(loader.phase == .idle || loader.phase == .loaded)
    }

    @Test("aplicar desconto megafona com o preço sugerido e marca sucesso")
    func aplicarDescontoComSucesso() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%")
            ]
        )
        let loader = DiscountCandidatesLoader(client: client)
        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        loader.applyDiscount(for: 1)
        await waitUntil { loader.candidates.first?.status != .megaphoning }

        #expect(loader.candidates.first?.status == .succeeded)
        #expect(await client.appliedDiscounts[1] == 100)
        #expect(await client.megaphonedIDs == [1])
    }

    @Test("falha ao aplicar desconto marca o item com a mensagem de erro")
    func aplicarDescontoComFalha() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)],
            failuresByProductID: [1: .http(status: 429, message: "calma lá")],
            exposuresByProductID: [
                1: MegaphoneExposure(productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%")
            ]
        )
        let loader = DiscountCandidatesLoader(client: client)
        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        loader.applyDiscount(for: 1)
        await waitUntil { loader.candidates.first?.status != .megaphoning }

        #expect(loader.candidates.first?.status == .failed("calma lá"))
    }

    @Test("token CSRF recusado é renovado e o desconto sai aplicado do mesmo jeito")
    func aplicarDescontoRenovaTokenRecusado() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)],
            csrfRejectionsRemaining: 1,
            exposuresByProductID: [
                1: MegaphoneExposure(productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%")
            ]
        )
        let loader = DiscountCandidatesLoader(client: client)
        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        loader.applyDiscount(for: 1)
        await waitUntil { loader.candidates.first?.status != .megaphoning }

        #expect(loader.candidates.first?.status == .succeeded)
        #expect(await client.usedTokens == ["token-1", "token-2"])
    }

    @Test("um segundo toque enquanto já está aplicando não dispara outra chamada")
    func duploToqueNaoDuplica() async {
        let client = StubEnjoeiClient(
            pages: [EnjoeiFixtures.page(ids: [1], endCursor: nil)],
            exposuresByProductID: [
                1: MegaphoneExposure(productID: 1, kind: .maximumAfterDiscount, priceToIncreaseExposure: 100, discountLabel: "- 20%")
            ]
        )
        let loader = DiscountCandidatesLoader(client: client)
        loader.load(sellerID: 1)
        await loader.waitUntilFinished()

        loader.applyDiscount(for: 1)
        loader.applyDiscount(for: 1)
        await waitUntil { loader.candidates.first?.status != .megaphoning }

        #expect(await client.megaphonedIDs == [1])
    }

    /// Espera uma condição sem prender o teste para sempre se algo der errado.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
    }
}
