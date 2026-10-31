import XCTest

/// "postar em outra loja" na aba publicados, em cima das contas inventadas do modo de demonstração
/// (`DemoMode`): antonia, loja B e loja C com sessão aberta, loja A com a sessão vencida — que por
/// isso nunca aparece como destino. Cada teste anexa capturas de tela, pra comparar com o card
/// `PostToOtherStore` do design system.
final class PostToOtherStoreUITests: XCTestCase {
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
        XCTAssertTrue(element(in: app.buttons, containing: "foto de").waitForExistence(timeout: 15))
    }

    @MainActor
    func testMenuDaLinhaPostaEmOutraLojaEMostraOAndamento() {
        let app = launchApp()
        openAccount("antonia", in: app)

        let moreActions = app.buttons["mais ações"].firstMatch
        XCTAssertTrue(moreActions.waitForExistence(timeout: 5))
        moreActions.tap()

        let postItem = element(in: app.buttons, containing: "postar em outra loja")
        XCTAssertTrue(postItem.waitForExistence(timeout: 5))
        postItem.tap()

        // As duas lojas com sessão aberta, com o @nick embaixo — a loja A (sessão vencida) não.
        let storeB = element(in: app.buttons, containing: "loja B")
        XCTAssertTrue(storeB.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app.buttons, containing: "loja C").exists)
        XCTAssertFalse(element(in: app.buttons, containing: "loja A").exists)
        attachScreenshot("submenu postar em", of: app)

        storeB.tap()
        let confirm = app.buttons["postar em loja B"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["postar este produto em loja B?"].exists)
        attachScreenshot("confirmar postar em loja B", of: app)
        confirm.tap()

        // A fila começa na hora: dependendo de quando a tela é lida, "na fila pra", "postando em…"
        // ou já "postado em" — e termina em "postado em loja B".
        // A linha junta ícone e texto num elemento só de acessibilidade — não é um `staticText`.
        let line = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'pra loja B' OR label CONTAINS 'em loja B'")
        ).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertTrue(
            element(in: app.descendants(matching: .any), containing: "postado em loja B").waitForExistence(timeout: 15)
        )
        attachScreenshot("postado em loja B", of: app)
    }

    @MainActor
    func testSelecionarEPostarEmPedeALojaEConfirma() {
        let app = launchApp()
        openAccount("antonia", in: app)

        app.buttons["selecionar"].tap()
        XCTAssertTrue(app.buttons["concluir seleção"].waitForExistence(timeout: 5))
        let postAction = app.buttons["postar em"]
        XCTAssertTrue(postAction.exists)
        // Sem nada marcado, à mostra mas sem responder, como as outras.
        XCTAssertFalse(postAction.isEnabled)

        let titles = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'prata 925'"))
        titles.element(boundBy: 0).tap()
        titles.element(boundBy: 1).tap()
        XCTAssertTrue(app.navigationBars["2 selecionados"].waitForExistence(timeout: 5))
        XCTAssertTrue(postAction.isEnabled)
        // Repostar não entra na barra de publicados — fica só no "..." de cada produto.
        XCTAssertTrue(app.buttons["inativar"].exists)
        XCTAssertFalse(app.buttons["repostar"].exists)

        postAction.tap()
        XCTAssertTrue(app.staticTexts["postar 2 em"].waitForExistence(timeout: 5))
        let storeB = element(in: app.buttons, containing: "loja B")
        let storeC = element(in: app.buttons, containing: "loja C")
        XCTAssertTrue(storeC.exists)
        // Na ordem da lista de contas, mesmo com o menu abrindo pra cima a partir da barra.
        XCTAssertLessThan(storeB.frame.minY, storeC.frame.minY)
        XCTAssertFalse(element(in: app.buttons, containing: "loja A").exists)
        attachScreenshot("menu postar 2 em", of: app)

        storeC.tap()
        let alert = app.alerts["postar 2 produtos em loja C?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["postar em loja C"].exists)
        attachScreenshot("confirmar postar 2 em loja C", of: app)

        alert.buttons["cancelar"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["2 selecionados"].exists)
    }
}
