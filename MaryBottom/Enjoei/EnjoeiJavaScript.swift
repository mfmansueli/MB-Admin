import Foundation

/// Os scripts que rodam dentro da WebView logada.
///
/// As chamadas autenticadas do Enjoei só funcionam de dentro da página: replicar os cookies para
/// fora (URLSession) faz o servidor devolver 401 e ainda derruba o `remember_user_token`. Então
/// identificação e megafone acontecem aqui, na mesma origem em que o usuário se logou.
nonisolated enum EnjoeiJavaScript {
    /// Descobre quem está logado, tentando as três pistas que a página oferece, nessa ordem:
    /// a API de usuário atual, o redirecionamento de `/minha-loja` e o link da loja no cabeçalho.
    static let identity = """
    const result = { csrf: "" };
    const meta = document.querySelector('meta[name="csrf-token"]');
    if (meta) { result.csrf = meta.getAttribute("content") || ""; }

    function nicknameFromPath(path) {
        const match = /\\/@([^\\/?#]+)/.exec(path || "");
        if (!match) { return null; }
        return match[1] === "minha-loja" ? null : match[1];
    }

    try {
        const response = await fetch("/api/v3/current_user.json", {
            credentials: "include",
            headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
        });
        result.currentUserStatus = response.status;
        if (response.ok) {
            const payload = await response.json();
            if (payload && payload.nickname) { result.nickname = payload.nickname; }
            if (payload && payload.id) { result.id = payload.id; }
        }
    } catch (error) {
        result.currentUserError = String(error);
    }

    if (!result.nickname) {
        try {
            const response = await fetch("/minha-loja", { credentials: "include" });
            result.myStoreStatus = response.status;
            result.nickname = nicknameFromPath(new URL(response.url).pathname);
        } catch (error) {
            result.myStoreError = String(error);
        }
    }

    if (!result.nickname) {
        const link = document.querySelector('header a[href^="/@"]')
            || document.querySelector('a[href^="/@"]');
        if (link) { result.nickname = nicknameFromPath(link.getAttribute("href")); }
    }

    return result;
    """

    /// Megafona um produto pela mesma rota que o site usa. Devolve status e corpo para o app poder
    /// explicar a falha em vez de só dizer que não deu.
    ///
    /// `newPrice` chega como `null` quando é pra megafonar sem desconto — nesse caso `new_price`
    /// nem entra no corpo (mandar `null` pro Enjoei não é a mesma coisa que omitir o campo).
    static let megaphone = """
    const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
    };
    if (token) { headers["X-CSRF-Token"] = token; }

    const body = { version: "v2", product_id: productID };
    if (newPrice !== null && newPrice !== undefined) { body.new_price = newPrice; }

    const response = await fetch("/api/megaphones", {
        method: "POST",
        credentials: "include",
        headers: headers,
        body: JSON.stringify(body)
    });
    return { status: response.status, body: await response.text() };
    """

    /// Relê o token CSRF da página — ele gira junto com a sessão.
    static let csrfToken = """
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? (meta.getAttribute("content") || "") : "";
    """

    /// Consulta se cada produto pede desconto pra alcançar exposição máxima no megafone — a mesma
    /// rota que o site chama antes de abrir o popup de desconto. `productIDs` chega pronto,
    /// separado por vírgula.
    static let megaphoneExposures = """
    const response = await fetch(`/api/megaphones/v2?product_ids=${productIDs}&version=v2`, {
        credentials: "include",
        headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
    });
    return { status: response.status, body: await response.text() };
    """

    /// Lê o "template" de um produto — a mesma rota que o botão "duplicar" do site usa pra
    /// pré-preencher o formulário, com todos os campos e as fotos já com `image_public_id`.
    static let productTemplate = """
    const response = await fetch(`/api/similars/products/${productID}/template`, {
        credentials: "include",
        headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
    });
    return { status: response.status, body: await response.text() };
    """

    /// Cria um anúncio novo a partir de um corpo já montado (ver `ProductCreateRequest`) — usado
    /// pelo repost, depois de ler o template do produto original.
    static let createProduct = """
    const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
    };
    if (token) { headers["X-CSRF-Token"] = token; }

    const response = await fetch("/api/products/v2", {
        method: "POST",
        credentials: "include",
        headers: headers,
        body: requestBody
    });
    return { status: response.status, body: await response.text() };
    """

    /// Apaga um produto de vez — ação destrutiva e provavelmente irreversível, sem corpo no
    /// pedido; o id vai na própria URL.
    static let deleteProduct = """
    const headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-Requested-With": "XMLHttpRequest"
    };
    if (token) { headers["X-CSRF-Token"] = token; }

    const response = await fetch(`/produto/${productID}.json`, {
        method: "DELETE",
        credentials: "include",
        headers: headers
    });
    return { status: response.status, body: await response.text() };
    """
}
