import XCTest

/// Fluxos das telas que vieram depois da primeira fase do redesign — detalhe do erro, fila de
/// ações, comparar produtos e as abas inativos/preço esperto —, em cima das contas inventadas do
/// modo de demonstração (`DemoMode`, ligado por `-demo-mode`). Cada teste anexa capturas de tela ao
/// resultado, pra comparar com o mock do redesign.
final class SecondaryScreensUITests: XCTestCase {
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

    @MainActor
    private func openAccount(_ name: String, in app: XCUIApplication) {
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        // A foto de um produto diz que a lista chegou — a cápsula do filtro "todos os anúncios"
        // aparece antes disso.
        XCTAssertTrue(element(in: app.buttons, containing: "foto de").waitForExistence(timeout: 15))
    }

    /// No iPad/Mac a aba mostra a quantidade depois de carregar ("inativos (8)").
    @MainActor
    private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// No iPhone a lista de contas fica atrás da conta aberta; no iPad, sempre na barra lateral.
    @MainActor
    private func backToAccountsIfNeeded(in app: XCUIApplication) {
        let queueButton = element(in: app.buttons, containing: "fila de ações")
        guard !queueButton.isHittable else { return }
        let back = app.buttons["BackButton"]
        if back.exists {
            back.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue(queueButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDetalheDoErroMostraOQueFalhouETentarDeNovo() {
        let app = launchApp()
        openAccount("antonia", in: app)

        // No modo de demonstração, o 12º produto da antonia sempre falha com 504.
        app.buttons["megafonar"].tap()
        let stopButton = app.buttons["parar"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 15))
        sleep(16)
        stopButton.tap()
        XCTAssertTrue(app.buttons["megafonar"].waitForExistence(timeout: 15))

        // A lista só monta as linhas perto da tela — rola até a do produto que falhou existir; o
        // toque em si já rola o resto (ela pode estar embaixo da barra de baixo).
        let failureButton = app.buttons["falhou, ver detalhe do erro"].firstMatch
        for _ in 0..<8 where !failureButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(failureButton.waitForExistence(timeout: 5))
        failureButton.tap()

        XCTAssertTrue(element(in: app.staticTexts, containing: "megafone não foi").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.staticTexts, containing: "504").exists)
        XCTAssertTrue(element(in: app.buttons, containing: "diagnóstico técnico").exists)
        XCTAssertTrue(app.buttons["tentar de novo"].exists)
        attachScreenshot("detalhe do erro", of: app)

        app.buttons["fechar"].firstMatch.tap()
        XCTAssertTrue(element(in: app.staticTexts, containing: "megafone não foi").waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testFilaDeAcoesSeparaPorSituacao() {
        let app = launchApp()
        openAccount("antonia", in: app)

        // Repostar dois produtos põe dois itens na fila — o primeiro sai na hora, o segundo espera o
        // intervalo (1 minuto, o padrão).
        app.buttons["selecionar"].tap()
        let titles = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'prata 925'"))
        titles.element(boundBy: 0).tap()
        titles.element(boundBy: 1).tap()
        app.buttons["repostar"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["repostar"].tap()
        XCTAssertTrue(app.buttons["selecionar"].waitForExistence(timeout: 5))

        backToAccountsIfNeeded(in: app)
        element(in: app.buttons, containing: "fila de ações").tap()

        XCTAssertTrue(element(in: app.staticTexts, containing: "próxima ação em").waitForExistence(timeout: 15))
        // O intervalo escolhido sobrevive entre aberturas — só confere que o ritmo aparece.
        XCTAssertTrue(element(in: app.staticTexts, containing: "1 a cada").exists)
        XCTAssertTrue(app.staticTexts["na fila · 1"].exists)
        XCTAssertTrue(app.staticTexts["feitos · 1"].exists)
        attachScreenshot("fila de ações", of: app)

        app.buttons["pausar fila"].tap()
        XCTAssertTrue(app.staticTexts["fila pausada"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["continuar fila"].exists)
        attachScreenshot("fila pausada", of: app)

        app.buttons["fechar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["fila pausada"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCompararMostraParesEProdutosQueFaltam() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["antonia"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["loja B"].waitForExistence(timeout: 10))

        element(in: app.buttons, containing: "comparar").tap()
        let start = app.buttons["startComparison"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(element(in: app.staticTexts, containing: "produtos em comum").waitForExistence(timeout: 20))
        XCTAssertTrue(element(in: app.buttons, containing: "ver diferenças do par").exists)
        attachScreenshot("comparar produtos", of: app)

        // Os que faltam numa conta ficam embaixo dos 25 pares, e a lista só monta o que está à
        // vista — o filtro traz a seção pro topo.
        app.buttons["filtrar resultados"].tap()
        element(in: app.buttons, containing: "não encontrados em loja B").tap()
        XCTAssertTrue(element(in: app.staticTexts, containing: "só em antonia").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.buttons, containing: "postar em loja B").exists)
        attachScreenshot("comparar só em antonia", of: app)

        // Selecionar só marca quem falta numa conta; "todos" da seção conta na barra de cima.
        app.buttons["selecionar"].tap()
        app.buttons["selecionar todos em só em antonia"].tap()
        XCTAssertTrue(element(in: app.buttons, containing: "à fila").waitForExistence(timeout: 5))
        attachScreenshot("comparar selecionando", of: app)
        app.buttons["concluir seleção"].tap()

        app.buttons["nova comparação"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    @MainActor
    func testInativosSelecionaComBarraDeAcoes() {
        let app = launchApp()
        openAccount("antonia", in: app)

        tab("inativos", in: app).tap()
        XCTAssertTrue(element(in: app.staticTexts, containing: "inativo desde").waitForExistence(timeout: 15))

        app.buttons["selecionar"].tap()
        app.buttons["selecionar tudo"].tap()
        XCTAssertTrue(app.navigationBars["8 selecionados"].waitForExistence(timeout: 5))
        attachScreenshot("inativos selecionando", of: app)

        app.buttons["apagar"].tap()
        let alert = app.alerts["apagar 8 produtos?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["cancelar"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))

        app.buttons["concluir seleção"].tap()
        XCTAssertTrue(app.buttons["selecionar"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrecoEspertoSelecionaEAtivaPorUmBotaoSo() {
        let app = launchApp()
        openAccount("antonia", in: app)

        tab("sem preço esperto", in: app).tap()
        // O filtro padrão é "preço atual"; a cápsula "todos" mostra a lista inteira.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'todos'")).firstMatch.tap()
        XCTAssertTrue(element(in: app.staticTexts, containing: "varia de").waitForExistence(timeout: 15))

        app.buttons["selecionar"].tap()
        app.buttons["selecionar tudo"].tap()
        XCTAssertTrue(app.navigationBars["5 selecionados"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.buttons, containing: "ativar preço esperto em 5").exists)
        attachScreenshot("preço esperto selecionando", of: app)

        app.buttons["concluir seleção"].tap()
        XCTAssertTrue(app.buttons["selecionar"].waitForExistence(timeout: 5))
    }
}
