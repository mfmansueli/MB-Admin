import SwiftUI

/// Tela de status da fila de ações — postar (numa conta diferente ou repostar na mesma), apagar,
/// inativar e ativar produtos, todos no mesmo lugar. Aberta pelo botão da toolbar em "comparar
/// produtos" (e em "suas contas", já que a fila continua rodando com essas telas fechadas).
///
/// Em cima, o cartão com quanto falta pra próxima ação; embaixo dele, uma seção por situação
/// ("agora", "na fila", "com erro", "feitos"). Pausar e limpar ficam na barra de cima; histórico e
/// intervalo, na de baixo.
struct PostQueueView: View {
    let postQueue: PostQueue
    let poster: CrossAccountPoster

    @State private var isConfirmingClear = false
    @State private var isShowingHistory = false
    @Environment(\.dismiss) private var dismiss

    private var sections: PostQueueSections {
        PostQueueSections(items: postQueue.items, status: postQueue.status(for:))
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("fila de ações")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
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

    @ViewBuilder
    private var content: some View {
        if postQueue.items.isEmpty {
            ContentUnavailableView(
                "nenhuma ação na fila",
                systemImage: "list.bullet.rectangle",
                description: Text("reposte, apague ou poste produtos em outra conta — o andamento de cada ação aparece aqui.")
            )
        } else {
            let sections = sections
            // `LazyVStack` em vez de `List`: mesmo raciocínio de
            // `AccountPublishedTabView.productList` — no idiom otimizado do Mac Catalyst, `List`
            // vira `NSTableView`, caro pra reconstruir do zero.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    PostQueueScheduleCard(postQueue: postQueue, waitingCount: sections.items(in: .waiting).count)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    ForEach(sections.visibleKinds) { kind in
                        section(kind, items: sections.items(in: kind))
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func section(_ kind: PostQueueSections.Kind, items: [PostQueueItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.header(count: items.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.supportingText)
                .padding(.horizontal, 32)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    PostQueueRowView(
                        item: item,
                        status: postQueue.status(for: item),
                        failureDetail: postQueue.failureDetail(for: item),
                        productURL: poster.postedProductURLs[item.postTarget],
                        onRemove: { postQueue.remove(id: item.id) },
                        onRetry: { postQueue.retry(id: item.id) }
                    )
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Label("fechar", systemImage: "xmark")
            }
        }
        if !postQueue.items.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    postQueue.isPaused ? postQueue.resume() : postQueue.pause()
                } label: {
                    if postQueue.isPaused {
                        Label("continuar fila", systemImage: "play.fill")
                    } else {
                        Label("pausar fila", systemImage: "pause.fill")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("limpar fila", systemImage: "trash")
                }
                .tint(.statusFailure)
            }
        }
        // Botão de histórico como primeiro item da bottom bar — fica encostado na ponta leading,
        // com o `Spacer` logo depois empurrando o menu de intervalo pra ponta trailing.
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

    /// Presets oferecidos no menu de intervalo, de 30 segundos a 5 minutos.
    private static let intervalPresets: [TimeInterval] = [30, 60, 120, 180, 240, 300]

    /// Deixa escolher o intervalo entre ações da fila, de 30 segundos a 5 minutos. A escolha é
    /// persistida por `PostQueue.setInterval` — sobrevive a fechar e abrir o app.
    private var intervalMenu: some View {
        Menu {
            Picker("intervalo entre ações", selection: intervalBinding) {
                ForEach(Self.intervalPresets, id: \.self) { seconds in
                    Text(PostQueueStatusText.intervalLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(PostQueueStatusText.intervalLabel(postQueue.interval))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.supportingText)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel("intervalo entre ações")
        .accessibilityValue(PostQueueStatusText.pace(interval: postQueue.interval))
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
