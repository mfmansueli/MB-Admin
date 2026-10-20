import SwiftUI

/// Cabeçalho com a identificação de quem está logado.
struct UserHeaderView: View {
    let user: EnjoeiUser
    let megaphoneCount: Int
    let errorCount: Int

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 12) {
            // `CachedAsyncImage`, não `AsyncImage` — mesmo raciocínio de `AccountRowView`/
            // `ProductPhotoView`: sem isso, o avatar é redecodificado do zero toda vez que este
            // header re-renderiza (o que acontece a cada produto megafonado, via
            // `megaphoneCount`/`errorCount` mudando).
            CachedAsyncImage(url: user.avatarURL, maxPixelSize: 72 * displayScale) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 72, height: 72)
            .clipShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.title3.weight(.semibold))
                Text("@\(user.nickname)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(megaphoneCount) megafones · \(errorCount) com erro")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    UserHeaderView(
        user: EnjoeiUser(
            id: 28714888,
            nickname: "antonia-40d0aa",
            name: "antonia",
            avatarPublicID: nil,
            availableProductsCount: 1496
        ),
        megaphoneCount: 42,
        errorCount: 3
    )
    .padding()
}
