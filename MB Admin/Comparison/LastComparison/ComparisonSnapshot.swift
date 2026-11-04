import Foundation

/// A última comparação terminada, guardada pra continuar na tela depois de fechar (ou de reabrir o
/// app) até você começar outra. Guarda só o que **não** está em outro cache: as listas das duas lojas
/// como estavam, por que algum template ou foto falhou, e qual rodada era. As assinaturas das fotos
/// (cache de fotos) e os templates (descrição, tamanho, marca — cache de cada conta) já ficam salvos
/// à parte; reabrir refaz a evidência com eles, sem rede, e aplica as revisões manuais de agora.
nonisolated struct ComparisonSnapshot: Codable, Equatable, Sendable {
    /// Sobe quando o formato muda de um jeito que a versão antiga não lê — uma versão desconhecida
    /// é descartada (comparar de novo resolve).
    static let currentFormat = 1

    /// Uma das duas lojas, como a listagem veio.
    nonisolated struct Store: Codable, Equatable, Sendable {
        let accountID: EnjoeiAccountID
        let sellerID: Int
        let name: String
        let status: StoreListingStatus
        let products: [EnjoeiProduct]
        /// Por que o template de um produto não veio, quando foi tentado nesta comparação e falhou.
        let detailsFailures: [Int: String]
        /// Quando a listagem foi buscada — `nil` numa comparação salva antes de isso existir (vale
        /// `savedAt`, um pouco depois).
        var listedAt: Date?
    }

    let format: Int
    let savedAt: Date
    /// A rodada (`AccountComparisonResult.id`) — reabrir mantém o mesmo id.
    let runID: UUID
    let checkAllDetails: Bool
    let storeA: Store
    let storeB: Store
    /// As fotos que falharam na análise (as que deram certo ficam no cache de assinaturas).
    let photoFailures: [String: PhotoSignatureError]

    init(
        savedAt: Date,
        runID: UUID,
        checkAllDetails: Bool,
        storeA: Store,
        storeB: Store,
        photoFailures: [String: PhotoSignatureError]
    ) {
        format = Self.currentFormat
        self.savedAt = savedAt
        self.runID = runID
        self.checkAllDetails = checkAllDetails
        self.storeA = storeA
        self.storeB = storeB
        self.photoFailures = photoFailures
    }

    /// A comparação envolve a conta (pra esquecer quando ela sai do app).
    func involves(_ accountID: EnjoeiAccountID) -> Bool {
        storeA.accountID == accountID || storeB.accountID == accountID
    }
}
