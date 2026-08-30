import SwiftUI

/// Cabeçalho com a identificação de quem está logado.
struct UserHeaderView: View {
    let user: EnjoeiUser

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.avatarURL) { image in
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
                if let count = user.availableProductsCount {
                    Text("\(count) produtos à venda")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
        )
    )
    .padding()
}
