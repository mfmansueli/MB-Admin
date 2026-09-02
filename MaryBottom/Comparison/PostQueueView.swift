import SwiftUI

/// Tela de status da fila de ações — postar (numa conta diferente ou repostar na mesma) e apagar
/// produtos, todos no mesmo lugar. Aberta pelo botão da toolbar em "comparar produtos" (e em
/// "suas contas", já que a fila continua rodando com essas telas fechadas).
struct PostQueueView: View {
    let postQueue: PostQueue
    let poster: CrossAccountPoster

    @State private var isConfirmingClear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if postQueue.items.isEmpty {
                    ContentUnavailableView(
                        "nenhuma ação na fila",
                        systemImage: "list.bullet.rectangle",
                        description: Text("reposte, apague ou poste produtos em outra conta — o andamento de cada ação aparece aqui.")
                    )
                } else {
                    List {
                        if postQueue.isPaused {
                            Section {
                                Label("fila pausada — toque em continuar quando quiser.", systemImage: "pause.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else if postQueue.isRunning {
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
            .navigationTitle("fila de ações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // `.fixedSize()` evita o texto truncar ("fe...") no Mac (idiom otimizado) —
                    // sem isso, o botão encolhe pro tamanho de uma "pill" fixa em vez de acompanhar
                    // o texto.
                    Button("fechar") { dismiss() }
                        .fixedSize()
                }
                if !postQueue.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(postQueue.isPaused ? "continuar" : "pausar fila") {
                            postQueue.isPaused ? postQueue.resume() : postQueue.pause()
                        }
                        .fixedSize()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("limpar fila", role: .destructive) {
                            isConfirmingClear = true
                        }
                        .fixedSize()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    intervalMenu
                }
            }
            .confirmationDialog(
                "limpar toda a fila de ações?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("limpar fila", role: .destructive) {
                    postQueue.removeAll()
                }
                Button("cancelar", role: .cancel) {}
            } message: {
                Text("remove todos os itens da fila — uma ação já em andamento termina normalmente, só não entra mais nenhuma depois dela.")
            }
        }
    }

    /// Contagem regressiva até o próximo item da fila poder começar — só faz sentido pra postar
    /// (o cooldown é o limite do Enjoei pra criar produto); apagar/inativar/ativar não esperam isso.
    @ViewBuilder
    private var cooldownStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let label = nonPostActionLabel {
                Label(label, systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            } else if let cooldownUntil = poster.cooldownUntil, poster.isInCooldown {
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

    /// Texto pro item em voo quando não é uma postagem — essas ações não têm cooldown nenhum pra
    /// contar, então a barra só mostra que estão rolando agora.
    private var nonPostActionLabel: String? {
        switch postQueue.currentItem?.kind {
        case .delete: "apagando agora…"
        case .inactivate: "inativando agora…"
        case .activate: "ativando agora…"
        case .post, nil: nil
        }
    }

    /// Deixa escolher o intervalo entre ações da fila, de 1 a 5 minutos — mesmo padrão de
    /// Menu+Picker do seletor de ação em massa (`InactiveProductsListView.bulkActionSelector`).
    private var intervalMenu: some View {
        Menu {
            Picker("intervalo entre ações", selection: intervalBinding) {
                ForEach(1...5, id: \.self) { minutes in
                    Text("\(minutes) min").tag(TimeInterval(minutes * 60))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text("\(Int(postQueue.interval / 60)) min")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
    }

    /// `PostQueue` é uma classe (`@Observable`, não `@Bindable` aqui) — sem açúcar de `$`, o
    /// binding pro Picker precisa ser montado à mão.
    private var intervalBinding: Binding<TimeInterval> {
        Binding(
            get: { postQueue.interval },
            set: { postQueue.interval = $0 }
        )
    }
}

#Preview {
    let poster = CrossAccountPoster()
    PostQueueView(
        postQueue: PostQueue(poster: poster, accountsProvider: { [] }),
        poster: poster
    )
}
