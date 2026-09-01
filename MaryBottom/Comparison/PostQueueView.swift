import SwiftUI

/// Tela de status da fila de publicação — aberta pelo botão da toolbar em "comparar produtos" (e
/// em "suas contas", já que a fila continua rodando com essas telas fechadas).
struct PostQueueView: View {
    let postQueue: PostQueue
    let poster: CrossAccountPoster

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if postQueue.items.isEmpty {
                    ContentUnavailableView(
                        "fila vazia",
                        systemImage: "list.bullet.rectangle",
                        description: Text("selecione produtos em \"comparar produtos\" pra adicionar aqui.")
                    )
                } else {
                    List {
                        if postQueue.isRunning {
                            Section {
                                cooldownStatus
                            }
                        }
                        Section {
                            ForEach(postQueue.items) { item in
                                PostQueueRowView(
                                    item: item,
                                    status: postQueue.status(for: item),
                                    productURL: poster.postedProductURLs[item.product.id],
                                    onRemove: { postQueue.remove(id: item.id) }
                                )
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("fila de publicação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // `.fixedSize()` evita o texto truncar ("fe...") no Mac (idiom otimizado) —
                    // sem isso, o botão encolhe pro tamanho de uma "pill" fixa em vez de acompanhar
                    // o texto.
                    Button("fechar") { dismiss() }
                        .fixedSize()
                }
            }
        }
    }

    /// Contagem regressiva até o próximo item da fila poder começar.
    @ViewBuilder
    private var cooldownStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let cooldownUntil = poster.cooldownUntil, poster.isInCooldown {
                let remaining = Int(cooldownUntil.timeIntervalSinceNow.rounded(.up))
                Label(
                    "próxima publicação em \(String(format: "%d:%02d", remaining / 60, remaining % 60))",
                    systemImage: "clock"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            } else {
                Label("publicando agora…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            }
        }
    }
}

#Preview {
    let poster = CrossAccountPoster()
    PostQueueView(
        postQueue: PostQueue(poster: poster, accountsProvider: { [] }),
        poster: poster
    )
}
