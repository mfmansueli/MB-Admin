#if DEBUG
import Foundation

/// `EnjoeiClientProtocol` de mentira do `DemoMode` — devolve o `DemoCatalog` da conta, com um pouco
/// de demora em cada chamada pra os estados intermediários (buscando, megafonando) aparecerem na
/// tela como num uso de verdade. Nunca sai pra rede.
actor DemoEnjoeiClient: EnjoeiClientProtocol {
    private let profile: DemoCatalog.Profile
    private let pageSize = 25
    private var csrfCount = 0

    init(profile: DemoCatalog.Profile) {
        self.profile = profile
    }

    func currentUser(reloadingPage: Bool) async throws -> EnjoeiUser {
        await pause(milliseconds: 300)
        if profile.isSessionExpired { throw EnjoeiError.notAuthenticated }
        return profile.user
    }

    func storeProductsPage(sellerID: Int, after: String?) async throws -> StoreProductsPage {
        await pause(milliseconds: 250)
        let products = DemoCatalog.products(for: profile)
        let start = after.flatMap(Int.init) ?? 0
        let end = min(start + pageSize, products.count)
        return StoreProductsPage(
            products: Array(products[start..<end]),
            total: products.count,
            endCursor: end < products.count ? String(end) : nil
        )
    }

    func csrfToken() async throws -> String {
        csrfCount += 1
        return "demo-token-\(csrfCount)"
    }

    func megaphone(productID: Int, csrfToken: String, newPrice: Double?) async throws {
        await pause(milliseconds: 400)
        if DemoCatalog.megaphoneFails(productID: productID) {
            throw EnjoeiError.http(status: 504, message: nil)
        }
    }

    func megaphoneBatch(
        productIDs: [Int],
        csrfToken: String,
        delayMilliseconds: Int,
        onProgress: @escaping (Int, MegaphoneWebResponse) -> Void
    ) async throws -> String {
        for productID in productIDs {
            await pause(milliseconds: delayMilliseconds)
            let status = DemoCatalog.megaphoneFails(productID: productID) ? 504 : 200
            onProgress(productID, MegaphoneWebResponse(status: status))
        }
        return csrfToken
    }

    func megaphoneExposures(productIDs: [Int]) async throws -> [MegaphoneExposure] {
        await pause(milliseconds: 200)
        return DemoCatalog.exposures(for: profile, productIDs: productIDs)
    }

    func productTemplate(productID: Int) async throws -> ProductTemplate {
        await pause(milliseconds: 200)
        let product = DemoCatalog.products(for: profile).first { $0.id == productID }
        let price = Int((product?.currentPrice ?? 100) * 100)
        return ProductTemplate(
            title: product?.title ?? "produto",
            description: "descrição de exemplo do modo de demonstração.",
            brand: nil,
            used: false,
            price: price,
            originalPrice: Int((product?.originalPrice ?? 100) * 100),
            weight: "0.3",
            quantity: 1,
            category: .init(id: 327),
            size: nil,
            shipping: .init(type: "charge_by_weight", hasInsurance: true),
            photos: [],
            originPlanID: 1,
            smartPrice: nil
        )
    }

    func createProduct(_ request: ProductCreateRequest, csrfToken: String) async throws -> ProductCreateResponse {
        await pause(milliseconds: 600)
        return ProductCreateResponse(path: "produto-demo-novo")
    }

    func deleteProduct(productID: Int, csrfToken: String) async throws {
        await pause(milliseconds: 500)
    }

    func updateProductState(_ request: ProductStateUpdateRequest, productID: Int, csrfToken: String) async throws {
        await pause(milliseconds: 500)
    }

    func inactiveProductsPage(page: Int) async throws -> InactiveProductsPage {
        await pause(milliseconds: 300)
        return InactiveProductsPage(products: DemoCatalog.inactiveProducts(for: profile), maxPage: 1)
    }

    func smartPriceProductsPage(page: Int, tab: Bool) async throws -> SmartPriceProductsPage {
        await pause(milliseconds: 300)
        return SmartPriceProductsPage(products: DemoCatalog.smartPriceProducts(for: profile), currentPage: 1, totalPages: 1)
    }

    func setSmartPrice(productID: Int, activate: Bool, csrfToken: String) async throws {
        await pause(milliseconds: 400)
    }

    func reloadPage() async {}

    func releaseMemoryIfIdle() async {}

    /// Sem `throws`: cancelar a espera (pausar/parar a rodada) só encurta a demora — quem decide
    /// o que fazer com o cancelamento é o `MegaphoneRunner`, como com o client de verdade.
    private func pause(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
#endif
