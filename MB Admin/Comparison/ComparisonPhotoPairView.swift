import SwiftUI

/// As duas fotos de um par lado a lado — a de cada loja que ligou os dois (ou as capas, quando foi
/// só o texto). Cada uma abre em tamanho grande ao tocar, como em qualquer lista de produto.
struct ComparisonPhotoPairView: View {
    let photoA: String?
    let photoB: String?
    let titleA: String
    let titleB: String
    var size: CGFloat = 52

    var body: some View {
        HStack(spacing: 4) {
            photo(photoA, title: titleA)
            photo(photoB, title: titleB)
        }
    }

    private func photo(_ publicID: String?, title: String) -> some View {
        ProductPhotoView(
            photoURL: publicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .thumbnail) },
            largePhotoURL: publicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .card) },
            title: title,
            size: size
        )
    }
}
