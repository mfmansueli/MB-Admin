import SwiftUI

/// Detalhe de uma conta: identifica o usuário e conduz o megafone da loja dele.
struct AccountDetailView: View {
    let account: AccountSession

    @Environment(AccountsStore.self) private var accountsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Quantas vezes repetir a lista. Fica guardado entre execuções do app (0 = infinito). Por
    /// conta: com contas rodando em paralelo, uma preferência global faria trocar a velocidade de
    /// uma afetar silenciosamente as outras já em andamento.
    @AppStorage private var storedRounds: Int
    /// Intervalo entre um megafone e o próximo, em milissegundos.
    @AppStorage private var storedSpeed: Int

    @State private var filter: ProductFilter = .all

    private var runner: MegaphoneRunner { account.runner }
    private var keepAlive: MegaphoneKeepAlive { account.keepAlive }

    private enum ProductFilter {
        case all
        case discountOnly
    }

    init(account: AccountSession) {
        self.account = account
        _storedRounds = AppStorage(wrappedValue: 1, "megaphone.rounds.\(account.id)")
        _storedSpeed = AppStorage(wrappedValue: MegaphoneSpeed.standard.milliseconds, "megaphone.speed.\(account.id)")
    }

    private var rounds: MegaphoneRounds { MegaphoneRounds(rawValue: storedRounds) }
    private var speed: MegaphoneSpeed { MegaphoneSpeed(milliseconds: storedSpeed) }

    var body: some View {
        VStack(spacing: 16) {
            UserHeaderView(user: account.user) {
                runner.cancel()
                Task {
                    await accountsStore.logout(accountID: account.id)
                    dismiss()
                }
            }

            roundsMenu

            speedMenu

            MegaphoneProgressView(runner: runner)

            actionButtons

            filterPicker

            productList
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // Enquanto roda, o app segura a tela acesa e um áudio silencioso para não ser congelado
        // ao você trocar de app.
        .onChange(of: runner.isRunning) { _, isRunning in
            isRunning ? keepAlive.start() : keepAlive.stop()
        }
        // Vale mudar o intervalo no meio da rodada: o laço lê o valor a cada produto.
        .onChange(of: storedSpeed) { _, milliseconds in
            runner.delayBetweenProducts = MegaphoneSpeed(milliseconds: milliseconds).duration
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: keepAlive.applicationBecameActive()
            case .inactive, .background: keepAlive.applicationWentToBackground()
            @unknown default: break
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    runner.delayBetweenProducts = speed.duration
                    runner.reload(sellerID: account.user.id, rounds: rounds)
                } label: {
                    Label("recarregar produtos", systemImage: "arrow.clockwise")
                }
                .disabled(runner.isRunning)
            }
        }
        // Ao entrar na conta pela primeira vez, já busca os produtos sozinho — sem começar a
        // megafonar por conta própria (isso continua exigindo o toque explícito no botão).
        .task {
            guard runner.items.isEmpty, !runner.isRunning else { return }
            runner.load(sellerID: account.user.id)
        }
    }

    private func startLoading() {
        runner.delayBetweenProducts = speed.duration
        runner.start(sellerID: account.user.id, rounds: rounds)
    }

    private var roundsMenu: some View {
        Menu {
            Picker("repetições", selection: $storedRounds) {
                ForEach(MegaphoneRounds.presets) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            // Sem isso, o Menu trata o Picker como um submenu à parte ("repetições" com seta),
            // exigindo um segundo toque pra ver as opções — .inline mostra tudo de uma vez.
            .pickerStyle(.inline)
        } label: {
            HStack {
                Text("repetir a lista")
                Spacer()
                Text(rounds.label)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .disabled(runner.isRunning)
    }

    private var speedMenu: some View {
        Menu {
            Picker("intervalo", selection: $storedSpeed) {
                ForEach(MegaphoneSpeed.presets) { option in
                    Text(option.label).tag(option.milliseconds)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack {
                Text("intervalo entre megafones")
                Spacer()
                Text(speed.label)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
    }

    /// Só faz sentido pausar/parar quando já está megafonando de verdade — durante a busca (seja
    /// pelo carregamento automático ou pelo botão), não tem o que pausar ainda.
    private var isMegaphoning: Bool {
        switch runner.phase {
        case .megaphoning, .paused: true
        case .idle, .loadingProducts, .checkingExposure, .finished, .cancelled, .failed: false
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isMegaphoning {
            HStack(spacing: 12) {
                Button {
                    if runner.isPaused { runner.resume() } else { runner.pause() }
                } label: {
                    Label(
                        runner.isPaused ? "continuar" : "pausar",
                        systemImage: runner.isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    runner.cancel()
                } label: {
                    Label("parar", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
        } else if runner.isRunning {
            EmptyView()
        } else {
            Button {
                startLoading()
            } label: {
                Label(buttonTitle, systemImage: "megaphone.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var buttonTitle: String {
        switch rounds.rawValue {
        case ...0: "megafonar tudo sem parar"
        case 1: "megafonar todos os produtos"
        default: "megafonar tudo \(rounds.rawValue) vezes"
        }
    }

    @ViewBuilder
    private var filterPicker: some View {
        if !runner.items.isEmpty {
            Picker("filtro", selection: $filter) {
                Text("todos").tag(ProductFilter.all)
                Text("pede desconto").tag(ProductFilter.discountOnly)
            }
            .pickerStyle(.segmented)
        }
    }

    private var filteredItems: [MegaphoneItem] {
        switch filter {
        case .all:
            runner.items
        case .discountOnly:
            runner.items.filter { $0.exposure?.kind.requiresDiscountDecision == true }
        }
    }

    @ViewBuilder
    private var productList: some View {
        if runner.items.isEmpty {
            ContentUnavailableView(
                "nenhum produto na fila",
                systemImage: "shippingbox",
                description: Text("toque em megafonar para buscar os produtos da sua loja.")
            )
            .frame(maxHeight: .infinity)
        } else if filteredItems.isEmpty {
            ContentUnavailableView(
                "nenhum produto pede desconto agora",
                systemImage: "checkmark.circle",
                description: Text("toque em \"todos\" pra ver a fila inteira.")
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(filteredItems) { item in
                    MegaphoneRowView(item: item, runner: runner)
                        .id(item.id)
                }
                .listStyle(.plain)
                .onChange(of: runner.currentItemID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }
}
