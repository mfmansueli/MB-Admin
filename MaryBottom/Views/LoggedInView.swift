import SwiftUI

/// Estado logado: identifica o usuário e conduz o megafone da loja dele.
struct LoggedInView: View {
    let user: EnjoeiUser

    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var runner: MegaphoneRunner
    @State private var keepAlive: MegaphoneKeepAlive
    /// Quantas vezes repetir a lista. Fica guardado entre execuções do app (0 = infinito).
    @AppStorage("megaphone.rounds") private var storedRounds = 1
    /// Intervalo entre um megafone e o próximo, em milissegundos.
    @AppStorage("megaphone.speed") private var storedSpeed = MegaphoneSpeed.standard.milliseconds

    init(user: EnjoeiUser, client: EnjoeiClientProtocol) {
        let runner = MegaphoneRunner(client: client)
        self.user = user
        _runner = State(initialValue: runner)
        _keepAlive = State(initialValue: MegaphoneKeepAlive(runner: runner))
    }

    private var rounds: MegaphoneRounds { MegaphoneRounds(rawValue: storedRounds) }
    private var speed: MegaphoneSpeed { MegaphoneSpeed(milliseconds: storedSpeed) }

    var body: some View {
        VStack(spacing: 16) {
            UserHeaderView(user: user) {
                runner.cancel()
                Task { await session.logout() }
            }

            roundsMenu

            speedMenu

            MegaphoneProgressView(runner: runner)

            actionButtons

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
                runner.start(sellerID: user.id, rounds: rounds)
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
