import SwiftUI

/// Botão da fila de ações na barra de cima — em "contas" e, no iPhone, também dentro de uma loja
/// (onde a lista de contas, com o botão dela, fica pra trás na pilha). A fila roda em segundo plano
/// mesmo com a tela de comparação fechada, então é por aqui que se confere o andamento. O selo
/// conta o que ainda está esperando a vez.
///
/// Lê `postQueue` no próprio `body`, não no de quem usa: a fila muda a cada ação, e a tela da loja
/// (lista de até milhares de produtos) não deve reavaliar inteira só por causa do selo. Quem mostra
/// a fila (`PostQueueView` num `.macCatalystSizedSheet`) continua sendo a tela dona do botão — um
/// `.sheet` preso num item de toolbar não é confiável.
struct PostQueueButton: View {
    let postQueue: PostQueue
    let action: () -> Void

    var body: some View {
        let pendingCount = postQueue.items.count
        Button(action: action) {
            PublishingQueueIcon(isAnimating: postQueue.isRunning)
                // Tamanho fixo, igual ao de antes do redesign — sem isso, o bezel padrão de toolbar
                // deixa o ícone (desenhado à mão, com um tamanho próprio) espremido/distorcido em
                // versões mais antigas do Mac Catalyst.
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    if pendingCount > 0 {
                        Text(pendingCount.formatted())
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.statusFailure, in: .capsule)
                            .offset(x: 6, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pendingCount > 0 ? "fila de ações, \(pendingCount) itens" : "fila de ações")
    }
}
