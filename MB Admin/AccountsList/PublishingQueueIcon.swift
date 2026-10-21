import Combine
import SwiftUI

/// Ícone da fila de ações — moldura com três linhas, uma em cada cor de status (falhou, em
/// andamento, deu certo). Parada, as cores ficam fixas; enquanto a fila processa algo, elas giram
/// de linha em linha, meio "luz de Natal", pra dar um sinal vivo de "rodando agora", já que a fila
/// continua em segundo plano mesmo com a tela dela fechada.
///
/// Desenhado à mão (moldura + 3 linhas), em vez de um símbolo do sistema com `.palette`: um SF
/// Symbol só expõe tantas cores quanto as camadas que a Apple desenhou nele (nesse caso, 2 —
/// moldura e conteúdo, sem separar linha por linha), então não dava pra colorir cada linha à
/// parte sem desenhar o ícone.
struct PublishingQueueIcon: View {
    var isAnimating = false

    private static let colors: [Color] = [.statusFailure, .statusInProgress, .statusSuccess]
    /// A última linha é mais curta, como uma lista que acaba no meio — mesmo desenho do mock. Em
    /// pontos: a moldura tem 21 de largura, menos 4 de respiro de cada lado.
    private static let lineWidths: [CGFloat] = [13, 13, 8]

    @State private var phase = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary, lineWidth: 1.3)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Self.lineWidths.indices, id: \.self) { line in
                    Capsule()
                        .fill(Self.colors[(phase + line) % Self.colors.count])
                        .frame(width: Self.lineWidths[line], height: 1.6)
                }
            }
        }
        .frame(width: 21, height: 17)
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
            guard isAnimating else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                phase += 1
            }
        }
        .onChange(of: isAnimating) { _, isAnimating in
            // Volta pras cores fixas ao parar, em vez de congelar no meio do giro.
            if !isAnimating { phase = 0 }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        PublishingQueueIcon()
        PublishingQueueIcon(isAnimating: true)
    }
}
