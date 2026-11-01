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
    func testFilaDeAcoesNaBarraDaLojaNoIPhone() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("no iPad/Mac a fila fica na barra lateral, sempre à vista")
        }
        let app = launchApp()
        openAccount("antonia", in: app)

        // Na barra de navegação da própria loja, sem voltar pra lista de contas.
        let queueButton = element(in: app.navigationBars.buttons, containing: "fila de ações")
        XCTAssertTrue(queueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(queueButton.isHittable)
        attachScreenshot("fila na barra da loja", of: app)

        // Selecionando, sai da barra junto com os outros botões.
        app.buttons["selecionar"].tap()
        XCTAssertTrue(app.buttons["concluir seleção"].waitForExistence(timeout: 5))
        XCTAssertFalse(queueButton.exists)
        app.buttons["concluir seleção"].tap()
        XCTAssertTrue(queueButton.waitForExistence(timeout: 5))

        queueButton.tap()
        XCTAssertTrue(app.navigationBars["fila de ações"].waitForExistence(timeout: 5))
        attachScreenshot("fila aberta da loja", of: app)

        app.buttons["fechar"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["fila de ações"].waitForNonExistence(timeout: 5))
        // Continua na loja, não na lista de contas.
        XCTAssertTrue(app.buttons["megafonar"].exists)
    }

    @MainActor
    func testEtiquetaDaLojaAcimaDasAbasNoIPhone() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("no iPad/Mac o nome da loja já está no título grande")
        }
        let app = launchApp()
        openAccount("antonia", in: app)

        // Sem nunca ter tocado em recarregar, só o nome — nada de quantidade de produtos.
        let badge = app.descendants(matching: .any)["loja da conta"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "loja antonia")
        // Em cima do seletor de abas.
        XCTAssertLessThan(badge.frame.maxY, tab("publicados", in: app).frame.minY)

        // Recarregar põe a data e a hora do toque na etiqueta.
        app.buttons["recarregar produtos"].tap()
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        let refreshed = NSPredicate(
            format: "label BEGINSWITH %@",
            "loja antonia, catálogo atualizado em \(formatter.string(from: .now)) às "
        )
        XCTAssertNotEqual(XCTWaiter.wait(for: [expectation(for: refreshed, evaluatedWith: badge)], timeout: 10), .timedOut)
        attachScreenshot("etiqueta da loja", of: app)

        // A quantidade de inativos fica no seletor, à vista de qualquer aba — a antonia do modo
        // demo tem 8. Publicados e preço esperto continuam só com o nome (a contagem deles está
        // nas cápsulas de filtro).
        XCTAssertTrue(app.buttons["inativos (8)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["publicados"].exists)

        // Trocar de aba não muda a loja nem a hora.
        let label = badge.label
        tab("inativos", in: app).tap()
        XCTAssertTrue(badge.exists)
        XCTAssertEqual(badge.label, label)

        // Selecionando, a barra de cima inteira dá lugar à seleção — a etiqueta sai junto.
        tab("publicados", in: app).tap()
        app.buttons["selecionar"].tap()
        XCTAssertTrue(app.buttons["concluir seleção"].waitForExistence(timeout: 5))
        XCTAssertFalse(badge.exists)
    }

    @MainActor
    func testInativosSemAtivarNoMenuDaLinha() {
        let app = launchApp()
        openAccount("antonia", in: app)
        tab("inativos", in: app).tap()

        // Menu de uma linha: repostar e apagar, sem ativar.
        let moreButton = app.buttons["mais ações"].firstMatch
        XCTAssertTrue(moreButton.waitForExistence(timeout: 10))
        moreButton.tap()
        XCTAssertTrue(app.buttons["repostar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["apagar produto"].exists)
        XCTAssertFalse(app.buttons["ativar produto"].exists)
        attachScreenshot("menu de um inativo", of: app)
    }

    @MainActor
    func testFilaDeAcoesSeparaPorSituacao() {
        let app = launchApp()
        openAccount("antonia", in: app)

        // Os dois intervalos começam no padrão (o modo demo zera a escolha a cada abertura): 30s
        // pra postar/repostar, 10s pra ativar/inativar/apagar. Esse vai pra 2 min aqui, pela seção
        // dele no menu — sem isso, a segunda inativação sairia antes das conferências.
        element(in: app.buttons, containing: "fila de ações").tap()
        let intervalMenu = app.buttons["intervalo entre ações"]
        XCTAssertTrue(intervalMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: intervalMenu.descendants(matching: .any), containing: "30s · 10s").exists
            || (intervalMenu.value as? String ?? "").contains("ativar, inativar e apagar: 1 a cada 10s"))
        intervalMenu.tap()
        // Um submenu por grupo, com o nome e o ritmo escolhido embaixo.
        let listingChangeMenu = element(in: app.buttons, containing: "ativar, inativar e apagar")
        XCTAssertTrue(listingChangeMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.buttons, containing: "postar e repostar").exists)
        attachScreenshot("menu de intervalos", of: app)
        listingChangeMenu.tap()
        // 5s e 10s só existem pra ativar/inativar/apagar.
        XCTAssertTrue(app.buttons["1 a cada 5s"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["1 a cada 10s"].exists)
        attachScreenshot("intervalos de ativar, inativar e apagar", of: app)
        app.buttons["1 a cada 2 min"].firstMatch.tap()
        XCTAssertTrue((intervalMenu.value as? String ?? "").contains("ativar, inativar e apagar: 1 a cada 2 min"))
        XCTAssertTrue((intervalMenu.value as? String ?? "").contains("postar e repostar: 1 a cada 30s"))
        app.buttons["fechar"].firstMatch.tap()

        // Inativar dois produtos põe dois itens na fila — o primeiro sai na hora, o segundo espera o
        // intervalo de ativar/inativar/apagar. Repostar não está mais na barra da seleção de publicados.
        app.buttons["selecionar"].tap()
        let titles = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'prata 925'"))
        titles.element(boundBy: 0).tap()
        titles.element(boundBy: 1).tap()
        app.buttons["inativar"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        // O intervalo não se escolhe aqui, mas a confirmação diz qual vai valer.
        XCTAssertTrue(element(in: alert.staticTexts, containing: "a fila faz 1 a cada 2 min").exists)
        alert.buttons["inativar"].tap()
        XCTAssertTrue(app.buttons["selecionar"].waitForExistence(timeout: 5))

        // Direto da loja: no iPhone o botão da fila também fica na barra dela; no iPad, na lateral.
        element(in: app.buttons, containing: "fila de ações").tap()

        XCTAssertTrue(element(in: app.staticTexts, containing: "próxima ação em").waitForExistence(timeout: 15))
        XCTAssertTrue(element(in: app.staticTexts, containing: "1 a cada 2 min pra ativar, inativar e apagar").exists)
        XCTAssertTrue(element(in: app.descendants(matching: .any), containing: "a seguir").exists)
        XCTAssertTrue(element(in: app.descendants(matching: .any), containing: "1 de 2 produtos processados").exists)
        XCTAssertTrue(element(in: app.descendants(matching: .any), containing: "na fila · 1").exists)
        XCTAssertTrue(element(in: app.descendants(matching: .any), containing: "feitos · 1").exists)
        attachScreenshot("fila de ações", of: app)

        // Limpar a fila é a vassoura azul, com confirmação dizendo que só a fila é limpa — nada
        // da loja é apagado. Cancelando, tudo continua lá.
        app.buttons["limpar fila"].tap()
        XCTAssertTrue(app.staticTexts["limpar só a fila de ações?"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.staticTexts, containing: "nenhum produto é apagado da loja").exists)
        attachScreenshot("confirmar limpar fila", of: app)
        // Saindo de um botão da barra, o iOS mostra a confirmação como popover, sem "cancelar" —
        // fecha tocando fora dele.
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.exists {
            dismissRegion.tap()
        } else {
            app.buttons["cancelar"].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["limpar só a fila de ações?"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(element(in: app.descendants(matching: .any), containing: "na fila · 1").exists)

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
        // Repostar e apagar — "ativar" saiu da barra.
        XCTAssertTrue(app.buttons["repostar"].exists)
        XCTAssertFalse(app.buttons["ativar"].exists)
        attachScreenshot("inativos selecionando", of: app)

        app.buttons["apagar"].tap()
        // Apagar tira da loja de vez: alerta alarmante, deixando claro que não é só a fila.
        let alert = app.alerts["⚠️ apagar 8 produtos da loja para sempre?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: alert.staticTexts, containing: "excluídos permanentemente na raiz da sua loja").exists)
        XCTAssertTrue(alert.buttons["apagar permanentemente"].exists)
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
        XCTAssertTrue(element(in: app.staticTexts, containing: "varia de").waitForExistence(timeout: 15))

        // Filtro padrão "preço atual": 7 produtos, 1 bloqueado (não entra na seleção).
        app.buttons["selecionar"].tap()
        app.buttons["selecionar tudo"].tap()
        XCTAssertTrue(app.navigationBars["6 selecionados"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.buttons, containing: "ativar preço esperto em 6").exists)
        attachScreenshot("preço esperto selecionando", of: app)

        app.buttons["concluir seleção"].tap()
        XCTAssertTrue(app.buttons["selecionar"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrecoEspertoAtivaEmTodosDoFiltro() {
        let app = launchApp()
        openAccount("antonia", in: app)

        tab("sem preço esperto", in: app).tap()
        XCTAssertTrue(element(in: app.staticTexts, containing: "varia de").waitForExistence(timeout: 15))

        // Sem selecionar nada: "ativar em N" vale pro que o filtro deixa na lista, menos o bloqueado.
        let activateCurrent = app.buttons["ativar em 6"]
        XCTAssertTrue(activateCurrent.waitForExistence(timeout: 5))
        attachScreenshot("preço esperto filtros e ativar", of: app)
        activateCurrent.tap()
        let alert = app.alerts["ativar preço esperto em 6 produtos com preço atual?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: alert.staticTexts, containing: "1 produto bloqueado fica de fora").exists)
        attachScreenshot("preço esperto confirmar ativar", of: app)
        alert.buttons["cancelar"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))

        // Trocar de filtro troca o que entra.
        element(in: app.buttons, containing: "preço alto, venda lenta").tap()
        let activateHigh = app.buttons["ativar em 3"]
        XCTAssertTrue(activateHigh.waitForExistence(timeout: 5))
        activateHigh.tap()
        let highAlert = app.alerts["ativar preço esperto em 3 produtos com preço alto, venda lenta?"]
        XCTAssertTrue(highAlert.waitForExistence(timeout: 5))
        highAlert.buttons["ativar"].tap()

        // Um de cada vez; no fim não sobra nada pra ativar nesse filtro.
        // Resumo da barra (iPad/Mac, as duas linhas juntas pro VoiceOver) ou subtítulo (iPhone).
        XCTAssertTrue(element(in: app.descendants(matching: .any), containing: "ativando… faltam").waitForExistence(timeout: 5))
        attachScreenshot("preço esperto ativando", of: app)
        let nothingLeft = app.buttons["ativar"]
        XCTAssertTrue(nothingLeft.waitForExistence(timeout: 20))
        XCTAssertFalse(nothingLeft.isEnabled)

        // Volta pro padrão — o filtro fica guardado por conta.
        element(in: app.buttons, containing: "preço atual").tap()
        XCTAssertTrue(activateCurrent.waitForExistence(timeout: 5))
    }
}
