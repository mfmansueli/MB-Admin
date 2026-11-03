import SwiftUI

/// Tela de status da fila de ações — postar (numa conta diferente ou repostar na mesma), apagar,
/// inativar e ativar produtos, todos no mesmo lugar. Aberta pelo botão da toolbar em "comparar
/// produtos" (e em "suas contas", já que a fila continua rodando com essas telas fechadas).
///
/// Em cima, o cartão com quanto falta pra próxima ação, o que roda agora e a seguir e o progresso;
/// embaixo dele, uma seção por situação ("agora", "na fila", "com erro", "feitos"), cada uma com o
/// título grande na cor da situação. Pausar e limpar (a vassoura azul — só esvazia a fila, nunca
/// apaga produto da loja) ficam na barra de cima; histórico e os dois intervalos
/// (postar/repostar/apagar e inativar), na de baixo.
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
                // Sem papel destrutivo de propósito: limpar a fila é faxina, nunca apaga nada da
                // loja — o vermelho e o alarme ficam só pra apagar produto (`PermanentDeleteConfirmation`).
                .confirmationDialog(
                    "limpar só a fila de ações?",
                    isPresented: $isConfirmingClear,
                    titleVisibility: .visible
                ) {
                    Button("limpar fila") {
                        postQueue.removeAll()
                    }
                    Button("cancelar", role: .cancel) {}
                } message: {
                    Text(
                        "é só uma faxina na fila de ações: nenhum produto é apagado da loja. as ações que ainda "
                            + "esperavam a vez saem da fila sem rodar, e uma que já está em andamento termina normalmente."
                    )
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
                    PostQueueScheduleCard(postQueue: postQueue, sections: sections)
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
            sectionHeader(kind, count: items.count)
                .padding(.horizontal, 32)
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

    /// Título grande, com o ícone e a cor da situação — azul "agora", vermelho "com erro", verde
    /// "feitos"; "na fila" no texto normal, com o relógio cinza. A contagem vem mais apagada, mas
    /// no mesmo texto ("na fila · 12"), pro VoiceOver ler junto.
    private func sectionHeader(_ kind: PostQueueSections.Kind, count: Int) -> some View {
        let color = Self.color(for: kind)
        let countText = Text(kind == .now ? "" : " · \(count)").foregroundStyle(.supportingText)
        return HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind == .waiting ? Color.supportingText : color)
                .accessibilityHidden(true)
            Text("\(Text(kind.title).foregroundStyle(color))\(countText)")
                .accessibilityLabel(kind.header(count: count))
        }
        .font(.title3.weight(.bold))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private static func color(for kind: PostQueueSections.Kind) -> Color {
        switch kind {
        case .now: .statusInProgress
        case .waiting: .primary
        case .failed: .statusFailure
        case .done: .statusSuccess
        }
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
            // Vassourinha mágica azul (desenhada à mão em `MagicBroom` — o SF Symbols não tem
            // vassoura), não lixeira vermelha: limpa só a fila, nunca a loja.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isConfirmingClear = true
                } label: {
                    Label("limpar fila", image: .magicBroom)
                }
                .tint(.statusInProgress)
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

    /// Os dois intervalos da fila num menu só: um submenu por grupo, com o nome dele e, embaixo, o
    /// ritmo escolhido ("inativar / 1 a cada 15s") — postar/repostar/apagar (30s a 5 min) e
    /// inativar (15s a 5 min). `Section` com um `Picker` em linha não mostrava o título no menu, e
    /// as duas listas iguais ficavam sem dizer qual era qual. O rótulo da barra mostra os dois,
    /// postar primeiro ("30s · 15s"). `.menuOrder(.fixed)`:
    /// abrindo pra cima a partir da barra de baixo, o sistema inverteria a ordem. A escolha é
    /// persistida por `PostQueue.setInterval` — sobrevive a fechar e abrir o app.
    private var intervalMenu: some View {
        let posting = postQueue.interval(for: .posting)
        let inactivating = postQueue.interval(for: .inactivating)
        return Menu {
            ForEach(PostQueueIntervalGroup.allCases, id: \.self) { group in
                Picker(selection: intervalBinding(for: group)) {
                    ForEach(group.presets, id: \.self) { seconds in
                        Text(PostQueueStatusText.pace(interval: seconds)).tag(seconds)
                    }
                } label: {
                    Text(group.title)
                    Text(PostQueueStatusText.pace(interval: postQueue.interval(for: group)))
                }
                .pickerStyle(.menu)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(PostQueueStatusText.intervalMenuLabel(posting: posting, inactivating: inactivating))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.supportingText)
            }
            .contentShape(.rect)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("intervalo entre ações")
        .accessibilityValue(
            PostQueueStatusText.intervalMenuAccessibilityValue(posting: posting, inactivating: inactivating)
        )
    }

    /// `PostQueue` é uma classe (`@Observable`, não `@Bindable` aqui) — sem açúcar de `$`, o
    /// binding pro Picker precisa ser montado à mão. O `set` passa por `setInterval` (não atribui
    /// direto) pra escolha persistir.
    private func intervalBinding(for group: PostQueueIntervalGroup) -> Binding<TimeInterval> {
        Binding(
            get: { postQueue.interval(for: group) },
            set: { postQueue.setInterval($0, for: group) }
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
