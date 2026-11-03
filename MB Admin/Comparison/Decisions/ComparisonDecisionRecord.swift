import Foundation
import SwiftData

/// `ComparisonDecision` em disco (no `SharedModelContainer` — uma decisão sempre envolve duas
/// contas). Colunas nativas; `pairID` (`ListingPairKey.storageID`) é a chave.
@Model
final class ComparisonDecisionRecord {
    @Attribute(.unique) var pairID: String
    var firstSellerID: Int
    var firstProductID: Int
    var secondSellerID: Int
    var secondProductID: Int
    var verdict: String
    var decidedAt: Date
    var firstCoverPublicID: String?
    var firstNormalizedTitle: String
    var secondCoverPublicID: String?
    var secondNormalizedTitle: String

    init(decision: ComparisonDecision) {
        pairID = decision.pairKey.storageID
        firstSellerID = decision.first.sellerID
        firstProductID = decision.first.productID
        secondSellerID = decision.second.sellerID
        secondProductID = decision.second.productID
        verdict = decision.verdict.rawValue
        decidedAt = decision.decidedAt
        firstCoverPublicID = decision.firstFingerprint.coverPublicID
        firstNormalizedTitle = decision.firstFingerprint.normalizedTitle
        secondCoverPublicID = decision.secondFingerprint.coverPublicID
        secondNormalizedTitle = decision.secondFingerprint.normalizedTitle
    }

    func update(from decision: ComparisonDecision) {
        verdict = decision.verdict.rawValue
        decidedAt = decision.decidedAt
        firstCoverPublicID = decision.firstFingerprint.coverPublicID
        firstNormalizedTitle = decision.firstFingerprint.normalizedTitle
        secondCoverPublicID = decision.secondFingerprint.coverPublicID
        secondNormalizedTitle = decision.secondFingerprint.normalizedTitle
    }

    /// `nil` se o veredito gravado não for um que esta versão conhece.
    var decision: ComparisonDecision? {
        guard let verdict = ComparisonDecision.Verdict(rawValue: verdict) else { return nil }
        return ComparisonDecision(
            (
                ListingKey(sellerID: firstSellerID, productID: firstProductID),
                ListingFingerprint(coverPublicID: firstCoverPublicID, normalizedTitle: firstNormalizedTitle)
            ),
            (
                ListingKey(sellerID: secondSellerID, productID: secondProductID),
                ListingFingerprint(coverPublicID: secondCoverPublicID, normalizedTitle: secondNormalizedTitle)
            ),
            verdict: verdict,
            decidedAt: decidedAt
        )
    }
}
