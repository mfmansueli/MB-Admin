import SwiftUI

/// Foto da conta na lista — enquanto a foto não chega (ou a conta não tem uma), a inicial do nome
/// sobre o coral da marca, o único lugar fora do ícone onde a cor da marca aparece. Sessão vencida
/// apaga a foto pra cinza, junto com a linha de status vermelha da row. Com uma rodada em aberto,
/// um anel de progresso em volta da foto.
struct AccountAvatarView: View {
    let user: EnjoeiUser
    var size: CGFloat = 60
    var isDimmed = false
    /// `nil` sem rodada em aberto (ou sem fração conhecida) — sem anel.
    var progress: Double?
    var progressStyle = AnyShapeStyle(.tint)

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // `CachedAsyncImage`, não `AsyncImage`: mesmo raciocínio de `ProductPhotoView` — sem isso,
        // o avatar é redecodificado do zero toda vez que essa row sai e volta pra área visível.
        CachedAsyncImage(url: user.avatarURL, maxPixelSize: size * displayScale) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            initialPlaceholder
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .grayscale(isDimmed ? 1 : 0)
        .opacity(isDimmed ? 0.6 : 1)
        // Por cima, não em volta no layout: a row não muda de tamanho nem pula quando a rodada
        // começa ou termina — o anel só ocupa a folga que já existe ao redor da foto.
        .overlay {
            if let progress {
                ProgressRing(progress: progress, size: size + 10, lineWidth: 3)
                    .foregroundStyle(progressStyle)
            }
        }
        .accessibilityHidden(true)
    }

    private var initialPlaceholder: some View {
        Circle()
            .fill(isDimmed ? Color(uiColor: .systemGray5) : .brandAvatarBackground)
            .overlay {
                Text(user.name.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(isDimmed ? Color.supportingText : .brandAvatarForeground)
            }
    }
}

#Preview {
    HStack(spacing: 24) {
        AccountAvatarView(user: EnjoeiUser(id: 1, nickname: "antonia", name: "antonia", avatarPublicID: nil, availableProductsCount: nil))
        AccountAvatarView(
            user: EnjoeiUser(id: 3, nickname: "mary", name: "mary", avatarPublicID: nil, availableProductsCount: nil),
            progress: 0.48,
            progressStyle: AnyShapeStyle(Color.statusInProgress)
        )
        AccountAvatarView(
            user: EnjoeiUser(id: 2, nickname: "loja-a", name: "loja A", avatarPublicID: nil, availableProductsCount: nil),
            isDimmed: true
        )
    }
    .padding()
}
