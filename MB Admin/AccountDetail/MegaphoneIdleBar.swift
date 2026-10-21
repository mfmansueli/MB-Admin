import SwiftUI

/// Barra de "megafonar" parada no iPad/Mac — repetições · intervalo à esquerda, "megafonar" à
/// direita, numa cápsula de vidro com a mesma largura do painel do megafone (que toma o lugar dela
/// quando a rodada começa). Desenhada à mão em vez de itens da barra de baixo do sistema: no Mac a
/// barra do sistema reduz cada item ao ícone, e "megafonar" ficava só um megafone, sem nome, e o
/// menu só com as setinhas, sem dizer quantas vezes nem o intervalo.
///
/// No iPhone continua a barra do sistema — lá ela divide espaço com a lupa da busca minimizada.
struct MegaphoneIdleBar: View {
    @Binding var rounds: Int
    @Binding var speedMilliseconds: Int
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MegaphoneSettingsMenu(rounds: $rounds, speedMilliseconds: $speedMilliseconds)
                .menuStyle(.button)
                .buttonStyle(.neutral)
            Spacer(minLength: 0)
            Button(action: onStart) {
                Label("megafonar", systemImage: "megaphone.fill")
            }
            .buttonStyle(.tinted(.accentColor, size: 48))
        }
        .padding(12)
        .glassSurface(in: .capsule)
        .frame(maxWidth: 660)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    VStack {
        Spacer()
        MegaphoneIdleBar(rounds: .constant(5), speedMilliseconds: .constant(900)) {}
    }
}
