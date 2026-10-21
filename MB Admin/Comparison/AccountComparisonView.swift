import SwiftUI

/// Conteúdo do sheet aberto pelo botão "comparar produtos" em "suas contas": escolhe duas contas
/// logadas e mostra quais produtos parecem ser o mesmo item nas duas, e quais só existem numa. O
/// resultado em si (busca, filtro, seleção múltipla, as três seções) vive em
/// `ComparisonResultView` — só criado depois que uma comparação termina, e aí ocupa a tela toda
/// (as contas comparadas vão pro subtítulo); "nova comparação" volta pra escolha das contas.
struct AccountComparisonView: View {
    let accounts: [AccountSession]

    @State private var accountAID: EnjoeiAccountID?
    @State private var accountBID: EnjoeiAccountID?
    @State private var loader = AccountComparisonLoader()
    @State private var isShowingQueue = false
    /// Além do título, busca a descrição de cada produto das duas contas antes de comparar — mais
    /// precisa, mas uma chamada de rede por produto (sem lote), então demorada numa loja grande.
    @State private var isFullComparison = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountsStore.self) private var accountsStore

    private var poster: CrossAccountPoster { accountsStore.poster }

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
        .onAppear(perform: preselectAccounts)
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
                postQueue: accountsStore.postQueue
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
                    VStack(alignment: .leading, spacing: 4) {
                        accountPicker("conta A", selection: $accountAID, excluding: accountBID)
                        detailsStatsText(for: accountA)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        cooldownStatus
                    }
                    .padding(.top, 34)
                    VStack(alignment: .leading, spacing: 4) {
                        accountPicker("conta B", selection: $accountBID, excluding: accountAID)
                        detailsStatsText(for: accountB)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("comparação completa", isOn: $isFullComparison)
                    if isFullComparison {
                        // Descrição já salva de uma comparação anterior sempre entra, com ou sem o
                        // toggle — ele só decide se busca o que ainda falta pela rede agora.
                        Text("mais precisa, mas demorada: busca a descrição de cada produto que ainda não tiver, uma requisição por vez.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    guard let accountA, let accountB else { return }
                    loader.compare(accountA: accountA, accountB: accountB, fullComparison: isFullComparison)
                } label: {
                    // `.onTint`: o estilo proeminente pinta o texto de branco, que some em cima da
                    // ação principal no modo escuro (`#F2F2F7`).
                    Text("comparar")
                        .foregroundStyle(.onTint)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(accountA == nil || accountB == nil || isLoadingProducts || isFetchingDetails)
                // Distingue do "comparar" da lista de contas, por baixo da folha (testes de UI).
                .accessibilityIdentifier("startComparison")
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

    private var isLoadingProducts: Bool {
        if case .loadingProducts = loader.phase { return true }
        return false
    }

    @ViewBuilder
    private var resultView: some View {
        switch loader.phase {
        case .idle:
            ContentUnavailableView(
                "compare os produtos das duas contas",
                systemImage: "rectangle.on.rectangle",
                description: Text("escolha as duas contas acima e toque em \"comparar\".")
            )
            .frame(maxHeight: .infinity)
        case .loadingProducts(let loaded, let total):
            Spacer()
            if total > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: Double(loaded), total: Double(total))
                        .frame(maxWidth: 220)
                    Text("carregando produtos… \(loaded) de \(total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("carregando produtos…")
            }
            Spacer()
        case .fetchingDetails:
            Spacer()
            HStack(spacing: 24) {
                detailsFetchingPanel(for: accountA)
                detailsFetchingPanel(for: accountB)
            }
            Spacer()
        case .finished:
            // Com resultado, `content` mostra `ComparisonResultView` no lugar desta tela inteira.
            EmptyView()
        }
    }

    /// Progresso individual de uma conta buscando detalhes (`ProductDetailsLoader`), durante a
    /// "comparação completa" — as duas contas rodam ao mesmo tempo, cada uma com seu próprio
    /// `phase`, por isso dois painéis lado a lado em vez de um progresso combinado só.
    @ViewBuilder
    private func detailsFetchingPanel(for account: AccountSession?) -> some View {
        VStack(spacing: 8) {
            Text(account?.user.name ?? "")
                .font(.subheadline.weight(.semibold))
            if case .fetching(let fetched, let total) = account?.productDetailsLoader.phase {
                ProgressView(value: Double(fetched), total: Double(total))
                    .frame(maxWidth: 140)
                Text("buscando detalhes… \(fetched) de \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("buscando detalhes…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Quantos produtos dessa conta já têm descrição salva localmente — mostrado embaixo de cada
    /// seletor de conta, pra dar pra decidir se vale a pena rodar a comparação completa de novo
    /// (que busca tudo de novo pela API) ou se boa parte já está salva de uma vez anterior.
    @ViewBuilder
    private func detailsStatsText(for account: AccountSession?) -> some View {
        if let account, account.productDetailsLoader.totalCount > 0 {
            Text("\(account.productDetailsLoader.detailedCount) de \(account.productDetailsLoader.totalCount) produtos já têm detalhes salvos")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var isFetchingDetails: Bool {
        loader.phase == .fetchingDetails
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
        accounts.first { $0.id == accountAID }
    }

    private var accountB: AccountSession? {
        accounts.first { $0.id == accountBID }
    }

    /// Já pré-seleciona as duas primeiras contas, pra quem só tem duas logadas ir direto no botão.
    private func preselectAccounts() {
        guard accounts.count >= 2 else { return }
        if accountAID == nil { accountAID = accounts[0].id }
        if accountBID == nil { accountBID = accounts[1].id }
    }
}
