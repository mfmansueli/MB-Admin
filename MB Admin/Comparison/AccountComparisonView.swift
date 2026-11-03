import SwiftUI

/// Conteúdo do sheet aberto pelo botão "comparar produtos" em "suas contas": escolhe duas contas
/// logadas e compara os anúncios das duas pelas fotos (com o texto ajudando nas dúvidas) —
/// `AccountComparisonLoader` conduz, com progresso, "parar" e "continuar". O resultado em si (busca,
/// filtro, seleção, revisão manual) vive em `ComparisonResultView` — só criado depois que uma
/// comparação termina, e aí ocupa a tela toda; "nova comparação" volta pra escolha das contas.
///
/// O loader é o do app (`AccountsStore.comparisonLoader`), não desta tela: fechar e abrir de novo
/// mostra o mesmo resultado (ou a comparação ainda rodando), e depois de reabrir o app a última
/// comparação volta do disco — até você começar outra.
struct AccountComparisonView: View {
    let accounts: [AccountSession]

    @State private var isShowingQueue = false
    /// Busca o anúncio inteiro (descrição, tamanho, marca) de todo par, não só dos que ficaram em
    /// dúvida ou dividem a foto com outras versões — mais lento na primeira vez; o template fica
    /// salvo por 30 dias.
    @AppStorage("comparison.checkAllDetails") private var checkAllDetails = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountsStore.self) private var accountsStore

    private var poster: CrossAccountPoster { accountsStore.poster }
    private var loader: AccountComparisonLoader { accountsStore.comparisonLoader }

    var body: some View {
        NavigationStack {
            Group {
                if accounts.count < 2 {
                    ContentUnavailableView(
                        "é preciso pelo menos duas contas logadas",
                        systemImage: "person.2",
                        description: Text("adicione outra conta pra poder comparar os produtos.")
                    )
                } else {
                    content
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("comparar produtos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("fechar", systemImage: "xmark")
                    }
                }
                if isShowingResult {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            loader.reset()
                        } label: {
                            Label("nova comparação", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Mesmo círculo de tamanho fixo do botão equivalente em "suas contas" — sem
                    // isso, o bezel padrão de toolbar deixa o ícone espremido/distorcido em
                    // versões mais antigas do Mac Catalyst.
                    Button {
                        isShowingQueue = true
                    } label: {
                        Group {
                            if accountsStore.postQueue.isRunning {
                                PublishingQueueIcon()
                            } else {
                                Label("fila de ações", systemImage: "list.bullet.rectangle")
                                    .labelStyle(.iconOnly)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(.quaternary, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            preselectAccounts()
            showLastComparison()
        }
        .macCatalystSizedSheet(isPresented: $isShowingQueue) {
            PostQueueView(postQueue: accountsStore.postQueue, poster: poster)
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .finished(let result) = loader.phase, let accountA, let accountB {
            ComparisonResultView(
                result: result,
                accountA: accountA,
                accountB: accountB,
                poster: poster,
                postQueue: accountsStore.postQueue,
                onDecide: { verdict, match in Task { await loader.decide(verdict, for: match) } },
                onUndo: { match in Task { await loader.undoDecision(for: match) } },
                onDecideDuplicate: { verdict, group in Task { await loader.decideDuplicate(verdict, for: group) } },
                onUndoDuplicate: { group in Task { await loader.undoDuplicateDecision(for: group) } },
                onRetry: { loader.retry() }
            )
            // `result.id` é novo a cada comparação — sem isso, SwiftUI trata essa view como a
            // mesma de antes e busca/filtro/seleção de uma comparação anterior (ex.: trocar a conta
            // B e comparar de novo) sobrevivem pro resultado novo, mesmo sem fazer mais sentido nele.
            .id(result.id)
        } else {
            setupContent
        }
    }

    private var isShowingResult: Bool {
        if case .finished = loader.phase { return true }
        return false
    }

    private var setupContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    accountPicker("conta A", selection: accountSelection(\.accountAID), excluding: loader.accountBID)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        cooldownStatus
                    }
                    .padding(.top, 34)
                    accountPicker("conta B", selection: accountSelection(\.accountBID), excluding: loader.accountAID)
                        .frame(maxWidth: .infinity)
                }

                Toggle(isOn: $checkAllDetails) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("conferir a descrição de todos os pares")
                            .font(.subheadline)
                        Text("mais lento na primeira vez: busca o anúncio inteiro de cada produto pra checar aro, banho e marca.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(loader.isRunning)

                HStack(spacing: 8) {
                    Button {
                        startComparison(refreshing: false)
                    } label: {
                        // `.onTint`: o estilo proeminente pinta o texto de branco, que some em cima da
                        // ação principal no modo escuro (`#F2F2F7`).
                        Text("comparar")
                            .foregroundStyle(.onTint)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    // Distingue do "comparar" da lista de contas, por baixo da folha (testes de UI).
                    .accessibilityIdentifier("startComparison")

                    Button {
                        startComparison(refreshing: true)
                    } label: {
                        Label("atualizar", systemImage: "arrow.clockwise")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("refreshComparison")
                }
                .disabled(accountA == nil || accountB == nil || loader.isRunning)

                Text(
                    "\"atualizar\" compara como na primeira vez: lê de novo a descrição, o tamanho e as fotos dos anúncios "
                        + "em vez de usar o que ficou salvo das duas lojas — mais lento."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Depois de "nova comparação", o resultado anterior continua valendo até outra
                // comparação começar.
                if loader.phase == .idle, loader.hasLastResult {
                    Button("ver o último resultado", action: showLastComparison)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("showLastComparison")
                }
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            resultView
        }
    }

    /// Contagem regressiva do bloqueio de "postar em" — só aparece enquanto o bloqueio está ativo.
    @ViewBuilder
    private var cooldownStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let cooldownUntil = poster.cooldownUntil, poster.isInCooldown {
                let remaining = Int(cooldownUntil.timeIntervalSinceNow.rounded(.up))
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.supportingText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var resultView: some View {
        switch loader.phase {
        case .idle:
            ContentUnavailableView(
                "compare os produtos das duas contas",
                systemImage: "rectangle.on.rectangle",
                description: Text(
                    "escolha as duas contas acima e toque em \"comparar\". a comparação procura a mesma foto nos "
                        + "anúncios das duas lojas e usa título, descrição, preço inicial e marca pra separar as versões "
                        + "(aro, banho, cor). na primeira vez, uma loja grande demora mais: as fotos e os anúncios ficam "
                        + "salvos pras próximas."
                )
            )
            .frame(maxHeight: .infinity)
        case .restoring:
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text("abrindo a última comparação…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .loadingProducts(let loaded, let total):
            progress(total > 0 ? "carregando produtos… \(loaded) de \(total)" : "carregando produtos…", done: loaded, total: total)
        case .analyzingPhotos(let done, let total):
            progress(total > 0 ? "analisando fotos… \(done) de \(total)" : "analisando fotos…", done: done, total: total)
        case .fetchingDetails:
            Spacer()
            HStack(spacing: 24) {
                detailsFetchingPanel(for: accountA)
                detailsFetchingPanel(for: accountB)
            }
            cancelButton
            Spacer()
        case .matching:
            progress("comparando…", done: 0, total: 0)
        case .interrupted:
            ContentUnavailableView {
                Label("comparação interrompida", systemImage: "pause.circle")
            } description: {
                Text("o que já foi analisado ficou salvo. continuar retoma de onde parou.")
            } actions: {
                Button("continuar") { loader.resume() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("resumeComparison")
                Button("recomeçar") { loader.retry() }
            }
            .frame(maxHeight: .infinity)
        case .finished:
            // Com resultado, `content` mostra `ComparisonResultView` no lugar desta tela inteira.
            EmptyView()
        }
    }

    private func progress(_ text: String, done: Int, total: Int) -> some View {
        VStack(spacing: 8) {
            Spacer()
            if total > 0 {
                ProgressView(value: Double(min(done, total)), total: Double(total))
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            cancelButton
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var cancelButton: some View {
        Button("parar", role: .cancel) { loader.cancel() }
            .padding(.top, 8)
            .accessibilityIdentifier("cancelComparison")
    }

    /// Progresso de uma conta buscando o template (todas as fotos) dos anúncios que a capa sozinha
    /// não resolveu — as duas contas rodam ao mesmo tempo, cada uma com seu próprio `phase`.
    @ViewBuilder
    private func detailsFetchingPanel(for account: AccountSession?) -> some View {
        VStack(spacing: 8) {
            Text(account?.user.name ?? "")
                .font(.subheadline.weight(.semibold))
            if case .fetching(let fetched, let total) = account?.productDetailsLoader.phase {
                ProgressView(value: Double(fetched), total: Double(total))
                    .frame(maxWidth: 140)
                Text("buscando fotos e descrições… \(fetched) de \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                Text("buscando fotos e descrições…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func accountPicker(
        _ title: String,
        selection: Binding<EnjoeiAccountID?>,
        excluding otherID: EnjoeiAccountID?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(accounts.filter { $0.id != otherID }) { account in
                    Button(account.user.name) { selection.wrappedValue = account.id }
                }
            } label: {
                // Mesma row usada em "suas contas" — só troca a conta selecionada, sem duplicar
                // o layout dela aqui.
                if let account = accounts.first(where: { $0.id == selection.wrappedValue }) {
                    AccountRowView(account: account)
                } else {
                    Text("selecione uma conta")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var accountA: AccountSession? {
        accounts.first { $0.id == loader.accountAID }
    }

    private var accountB: AccountSession? {
        accounts.first { $0.id == loader.accountBID }
    }

    private func accountSelection(_ keyPath: ReferenceWritableKeyPath<AccountComparisonLoader, EnjoeiAccountID?>) -> Binding<EnjoeiAccountID?> {
        Binding(get: { loader[keyPath: keyPath] }, set: { loader[keyPath: keyPath] = $0 })
    }

    /// Já pré-seleciona as duas primeiras contas, pra quem só tem duas logadas ir direto no botão — e
    /// troca uma conta escolhida que não está mais logada.
    private func preselectAccounts() {
        guard accounts.count >= 2 else { return }
        let ids = Set(accounts.map(\.id))
        if let id = loader.accountAID, !ids.contains(id) { loader.accountAID = nil }
        if let id = loader.accountBID, !ids.contains(id) { loader.accountBID = nil }
        if loader.accountAID == nil { loader.accountAID = accounts.first { $0.id != loader.accountBID }?.id }
        if loader.accountBID == nil { loader.accountBID = accounts.first { $0.id != loader.accountAID }?.id }
    }

    /// "atualizar" (`refreshing`) esquece os templates salvos das duas contas antes — ver
    /// `AccountComparisonLoader.compare`.
    private func startComparison(refreshing: Bool) {
        guard let accountA, let accountB else { return }
        loader.compare(
            accountA: accountA,
            accountB: accountB,
            services: accountsStore.comparisonServices,
            matchMemory: accountsStore.comparisonMatches,
            checkAllDetails: checkAllDetails,
            refreshing: refreshing
        )
    }

    private func showLastComparison() {
        loader.showLastComparison(
            accounts: accounts,
            services: { accountsStore.comparisonServices },
            matchMemory: accountsStore.comparisonMatches
        )
    }
}
