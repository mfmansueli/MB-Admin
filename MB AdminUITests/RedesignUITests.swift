import XCTest

/// Fluxos principais do redesign, em cima das contas inventadas do modo de demonstração
/// (`DemoMode`, ligado por `-demo-mode`) — sem login de verdade nem chamada nenhuma ao Enjoei. Cada
/// teste anexa capturas de tela ao resultado, pra comparar com o mock do redesign.
final class RedesignUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo-mode"]
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(in query: XCUIElementQuery, containing text: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Título da tela pela barra de navegação, não pelo texto: no iPad (título grande inline) o texto
    /// que a acessibilidade expõe continua com o título anterior ("antonia") mesmo depois de a tela
    /// trocar pra "N selecionados" — só o identificador da barra acompanha.
    @MainActor
    private func navigationTitle(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars[title]
    }

    /// Abre a conta e espera os produtos carregarem (o botão "megafonar" só fica útil com a lista
    /// pronta — a seção "todos os anúncios" é o sinal).
    @MainActor
    private func openAccount(_ name: String, in app: XCUIApplication) {
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(element(in: app.buttons, containing: "todos os anúncios").waitForExistence(timeout: 15))
    }

    @MainActor
    func testListaDeContasMostraContasESessaoExpirada() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["antonia"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(in: app.staticTexts, containing: "sessão expirada").waitForExistence(timeout: 10))
        XCTAssertTrue(element(in: app.staticTexts, containing: "338 sucesso").exists)
        XCTAssertTrue(app.buttons["adicionar conta"].exists)
        XCTAssertTrue(element(in: app.buttons, containing: "fila de ações").exists)
        attachScreenshot("contas", of: app)
    }

    @MainActor
    func testPublicadosSeparaOsQuePedemDesconto() {
        let app = launchApp()
        openAccount("antonia", in: app)

        let discountHeader = element(in: app.buttons, containing: "pedem desconto")
        XCTAssertTrue(discountHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.buttons, containing: "aplicar desconto").exists)
        XCTAssertTrue(app.buttons["megafonar"].exists)
        attachScreenshot("publicados (parado)", of: app)

        // Recolher a seção esconde o botão de desconto das linhas dela.
        discountHeader.tap()
        XCTAssertTrue(element(in: app.buttons, containing: "aplicar desconto").waitForNonExistence(timeout: 5))
        attachScreenshot("publicados (desconto recolhido)", of: app)
    }

    @MainActor
    func testMegafonarMostraPainelComPausarEParar() {
        let app = launchApp()
        openAccount("antonia", in: app)
        // A lupa minimizada da barra de baixo (rótulo do sistema, no idioma do simulador).
        let searchButton = app.buttons.matching(NSPredicate(format: "label IN %@", ["Search", "Buscar"])).firstMatch
        XCTAssertTrue(searchButton.exists)

        app.buttons["megafonar"].tap()
        let stopButton = app.buttons["parar"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["acompanhar produto atual"].exists)
        // Com o painel no lugar da barra, a busca some em vez de ficar solta embaixo dele.
        XCTAssertFalse(searchButton.exists)
        // Espera alguns produtos passarem, pra ter megafonado/erro/na fila na tela ao mesmo tempo.
        sleep(4)
        attachScreenshot("megafonando", of: app)
        // O pedaço inteiro em voo fica `.megaphoning`, mas só o da vez aparece como em andamento.
        let inFlightRows = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'megafonando agora'"))
        XCTAssertLessThanOrEqual(inFlightRows.count, 1)

        app.buttons["pausar"].tap()
        XCTAssertTrue(app.buttons["continuar"].waitForExistence(timeout: 15))
        attachScreenshot("pausado", of: app)

        stopButton.tap()
        XCTAssertTrue(app.buttons["megafonar"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["parar"].exists)
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSelecionarEApagarPedeConfirmacao() {
        let app = launchApp()
        openAccount("antonia", in: app)

        app.buttons["selecionar"].tap()
        XCTAssertTrue(app.buttons["concluir seleção"].waitForExistence(timeout: 5))

        let titles = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'prata 925'"))
        titles.element(boundBy: 0).tap()
        titles.element(boundBy: 1).tap()
        XCTAssertTrue(navigationTitle("2 selecionados", in: app).waitForExistence(timeout: 5))
        attachScreenshot("seleção", of: app)

        app.buttons["apagar"].tap()
        let alert = app.alerts["apagar 2 produtos?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        attachScreenshot("confirmar apagar", of: app)

        alert.buttons["cancelar"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(navigationTitle("2 selecionados", in: app).exists)

        app.buttons["concluir seleção"].tap()
        XCTAssertTrue(app.buttons["selecionar"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSelecionarTodosDeUmaSecaoMantemOPercentualVisivel() {
        let app = launchApp()
        openAccount("antonia", in: app)

        app.buttons["selecionar"].tap()
        XCTAssertTrue(app.buttons["concluir seleção"].waitForExistence(timeout: 5))
        // Selecionando, o percentual de "pedem desconto" continua à mostra (só informativo).
        XCTAssertTrue(element(in: app.staticTexts, containing: "desconto sugerido de").exists)

        app.buttons["selecionar todos em pedem desconto"].tap()
        XCTAssertTrue(navigationTitle("3 selecionados", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["desmarcar todos em pedem desconto"].exists)
        attachScreenshot("seleção por seção", of: app)

        app.buttons["desmarcar todos em pedem desconto"].tap()
        XCTAssertTrue(navigationTitle("selecionar produtos", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testFotoAbreEmTelaCheiaEFecha() {
        let app = launchApp()
        openAccount("antonia", in: app)

        let photo = element(in: app.buttons, containing: "foto de")
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()

        let closeButton = app.buttons["fechar"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        attachScreenshot("foto em tela cheia", of: app)

        closeButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["megafonar"].exists)
    }
}
