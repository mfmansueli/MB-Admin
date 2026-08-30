import SwiftUI

/// Cabeçalho com a identificação de quem está logado.
struct UserHeaderView: View {
    let user: EnjoeiUser
    let onLogout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 52, height: 52)
            .clipShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.headline)
                Text("@\(user.nickname)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let count = user.availableProductsCount {
                    Text("\(count) produtos à venda")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("sair", role: .destructive, action: onLogout)
                .buttonStyle(.bordered)
                .controlSize(.small)
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
        onLogout: {}
    )
    .padding()
}
