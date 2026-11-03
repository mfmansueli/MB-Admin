import Foundation

/// Uma assinatura como fica no cache: a foto (pelo id público), o que foi calculado e quando os
/// bytes foram conferidos pela última vez.
nonisolated struct StoredPhotoSignature: Equatable, Sendable {
    let publicID: String
    let signature: PhotoSignature
    let verifiedAt: Date
}
