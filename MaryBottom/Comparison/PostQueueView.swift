import SwiftUI

/// Tela de status da fila de ações — postar (numa conta diferente ou repostar na mesma) e apagar
/// produtos, todos no mesmo lugar. Aberta pelo botão da toolbar em "comparar produtos" (e em
/// "suas contas", já que a fila continua rodando com essas telas fechadas).
struct PostQueueView: View {
    let postQueue: PostQueue
    let poster: CrossAccountPoster

    @State private var isConfirmingClear = false
    @State private var isShowingHistory = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // `cooldownStatus` fica fora do `List` de propósito — o `TimelineView` de dentro
                // dele tica a cada segundo, e o `List` por trás é um `UICollectionView` de verdade;
                // ticar dentro dele (mesmo só numa `Section`) parecia disparar, junto com o mesmo
                // `NavigationStack` que carrega `.toolbar`, o aviso "Unable to simultaneously
                // satisfy constraints" nos botões da toolbar a cada tick, com travamento percebido
                // durante a fila rodando de verdade. Como view irmã, fora do `List`, o tick de cada
                // segundo só invalida essa view pequena, sem tocar a maquinaria do `List`.
                if postQueue.isPaused {
                    pausedBanner
                } else if postQueue.isRunning {
                    cooldownStatus
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                Group {
                    if postQueue.items.isEmpty {
                        ContentUnavailableView(
                            "nenhuma ação na fila",
                            systemImage: "list.bullet.rectangle",
                            description: Text("reposte, apague ou poste produtos em outra conta — o andamento de cada ação aparece aqui.")
                        )
                    } else {
                        List {
                            ForEach(postQueue.items) { item in
                                PostQueueRowView(
                                    item: item,
                                    status: postQueue.status(for: item),
                                    failureDetail: postQueue.failureDetail(for: item),
                                    productURL: poster.postedProductURLs[item.postTarget],
                                    onRemove: { postQueue.remove(id: item.id) }
                                )
                            }
                        }
                        .listStyle(.plain)
                    }
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
                        // `.fixedSize()` (sem argumentos) força tamanho ideal nas duas direções —
                        // como o texto deste botão muda sozinho enquanto a fila roda em segundo
                        // plano ("pausar fila" ↔ "continuar"), a largura ideal muda a cada troca, o
                        // que parece brigar com o dimensionamento vertical/de colapso que o
                        // `_UIButtonBarButton` por trás do item de toolbar já faz sozinho (visto
                        // como "Unable to simultaneously satisfy constraints" no console, correlato
                        // com travamentos percebidos). Fixar só a horizontal evita reintroduzir o
                        // truncamento de texto original sem competir com a dimensão vertical.
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("limpar fila", role: .destructive) {
                            isConfirmingClear = true
                        }
                        .fixedSize()
                    }
                }
                // Botão de histórico como primeiro item da bottom bar — fica encostado na ponta
                // leading, com o `Spacer` logo depois empurrando o menu de intervalo pra ponta
                // trailing.
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isShowingHistory = true
                    } label: {
                        // `.titleAndIcon` explícito — a bottom bar, sem isso, mostra só o ícone.
                        Label("histórico", systemImage: "clock.arrow.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                    .fixedSize()
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
            .macCatalystSizedSheet(isPresented: $isShowingHistory) {
                PostHistoryView(postQueue: postQueue)
            }
        }
    }

    private var pausedBanner: some View {
        Label("fila pausada — toque em continuar quando quiser.", systemImage: "pause.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    /// Contagem regressiva até a próxima ação da fila poder começar — as quatro (postar, apagar,
    /// inativar, ativar) respeitam o mesmo `postQueue.interval`, então a mesma contagem vale pra
    /// qualquer uma; enquanto uma já está em voo, mostra o quê em vez de quando.
    @ViewBuilder
    private var cooldownStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let label = inFlightActionLabel {
                Label(label, systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            } else if let nextActionAt = postQueue.nextActionAt, nextActionAt > .now {
                let remaining = Int(nextActionAt.timeIntervalSinceNow.rounded(.up))
                Label(
                    "próxima ação em \(String(format: "%d:%02d", remaining / 60, remaining % 60))",
                    systemImage: "clock"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            } else {
                Label("processando agora…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            }
        }
    }

    /// Texto pro item em voo agora, por tipo de ação — enquanto isso está rolando, não tem "quando"
    /// pra contar, só o quê.
    private var inFlightActionLabel: String? {
        switch postQueue.currentItem?.kind {
        case .post: "postando agora…"
        case .delete: "apagando agora…"
        case .inactivate: "inativando agora…"
        case .activate: "ativando agora…"
        case nil: nil
        }
    }

    /// Presets oferecidos no menu de intervalo, de 30 segundos a 5 minutos.
    private static let intervalPresets: [TimeInterval] = [30, 60, 120, 180, 240, 300]

    /// "30s" abaixo de um minuto, "N min" a partir de 1 minuto.
    private static func intervalLabel(_ interval: TimeInterval) -> String {
        interval < 60 ? "\(Int(interval))s" : "\(Int(interval / 60)) min"
    }

    /// Deixa escolher o intervalo entre ações da fila, de 30 segundos a 5 minutos — mesmo padrão
    /// de Menu+Picker do seletor de ação em massa (`InactiveProductsListView.bulkActionSelector`).
    /// A escolha é persistida por `PostQueue.setInterval` — sobrevive a fechar e abrir o app.
    private var intervalMenu: some View {
        Menu {
            Picker("intervalo entre ações", selection: intervalBinding) {
                ForEach(Self.intervalPresets, id: \.self) { seconds in
                    Text(Self.intervalLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(Self.intervalLabel(postQueue.interval))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
    }

    /// `PostQueue` é uma classe (`@Observable`, não `@Bindable` aqui) — sem açúcar de `$`, o
    /// binding pro Picker precisa ser montado à mão. O `set` passa por `setInterval` (não atribui
    /// `postQueue.interval` direto) pra escolha persistir.
    private var intervalBinding: Binding<TimeInterval> {
        Binding(
            get: { postQueue.interval },
            set: { postQueue.setInterval($0) }
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
