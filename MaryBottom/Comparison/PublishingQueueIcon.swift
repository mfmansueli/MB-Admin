import Combine
import SwiftUI

/// Ícone da fila de publicação enquanto ela está processando algo — cada linha de dentro pisca
/// numa cor diferente, meio "luz de Natal", pra dar um sinal vivo de "rodando agora", já que a
/// fila continua em segundo plano mesmo com essa tela fechada.
///
/// Desenhado à mão (moldura + 3 linhas), em vez de um símbolo do sistema com `.palette`: um SF
/// Symbol só expõe tantas cores quanto as camadas que a Apple desenhou nele (nesse caso, 2 —
/// moldura e conteúdo, sem separar linha por linha), então não dava pra colorir cada linha à
/// parte sem desenhar o ícone.
struct PublishingQueueIcon: View {
    private static let colors: [Color] = [.red, .blue, .green]
    private static let lineCount = 3

    @State private var phase = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary, lineWidth: 1.3)
            VStack(spacing: 3) {
                ForEach(0..<Self.lineCount, id: \.self) { line in
                    Capsule()
                        .fill(Self.colors[(phase + line) % Self.colors.count])
                        .frame(height: 1.6)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 21, height: 17)
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                phase += 1
            }
        }
    }
}

#Preview {
    PublishingQueueIcon()
}
