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

    @State private var selectedTab: Tab = .queue

    private var runner: MegaphoneRunner { account.runner }
    private var keepAlive: MegaphoneKeepAlive { account.keepAlive }

    private enum Tab {
        case queue
        case discounts
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

            tabPicker

            tabContent
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
    }

    private var roundsMenu: some View {
        Menu {
            Picker("repetições", selection: $storedRounds) {
                ForEach(MegaphoneRounds.presets) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
        } label: {
            HStack {
                Text("repetir a lista")
                Spacer()
                Text(rounds.label)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
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
        } label: {
            HStack {
                Text("intervalo entre megafones")
                Spacer()
                Text(speed.label)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if runner.isRunning {
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
        } else {
            Button {
                runner.delayBetweenProducts = speed.duration
                runner.start(sellerID: account.user.id, rounds: rounds)
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

    private var tabPicker: some View {
        Picker("aba", selection: $selectedTab) {
            Text("megafone").tag(Tab.queue)
            Text("desconto").tag(Tab.discounts)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .queue:
            productList
        case .discounts:
            DiscountCandidatesListView(loader: account.discountCandidatesLoader, sellerID: account.user.id)
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
        } else {
            ScrollViewReader { proxy in
                List(runner.items) { item in
                    MegaphoneRowView(item: item)
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
