const container = document.querySelector("#modules");
const count = document.querySelector("#count");
const channel = document.querySelector("#channel");
const search = document.querySelector("#search");
const filters = [...document.querySelectorAll("[data-kind]")];
const dialog = document.querySelector("#document-dialog");
const documentTitle = document.querySelector("#document-title");
const documentContent = document.querySelector("#document-content");
const documentSource = document.querySelector("#document-source");
let modules = [];
let selectedKind = "all";
let documentRequest = 0;

function safePath(path) {
  return (
    typeof path === "string" &&
    /^[a-z0-9._/-]+$/.test(path) &&
    !path.startsWith("/") &&
    !path.split("/").includes("..")
  );
}

function element(tag, className, value) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (value !== undefined) node.textContent = value;
  return node;
}

function link(label, path, className) {
  if (!safePath(path)) return null;
  const node = element("a", className, label);
  node.href = `./${path}`;
  return node;
}

function externalLink(label, url) {
  try {
    const destination = new URL(url);
    if (destination.protocol !== "https:" && destination.protocol !== "http:")
      return null;
    const node = element("a", "text-link", label);
    node.href = destination.href;
    node.target = "_blank";
    node.rel = "noopener noreferrer";
    return node;
  } catch {
    return null;
  }
}

function appendInline(parent, source, baseURL) {
  const pattern = /(`[^`]+`|\[[^\]]+\]\([^)]+\))/g;
  let position = 0;
  for (const match of source.matchAll(pattern)) {
    parent.append(document.createTextNode(source.slice(position, match.index)));
    const token = match[0];
    if (token.startsWith("`")) {
      parent.append(element("code", "", token.slice(1, -1)));
    } else {
      const separator = token.indexOf("](");
      const label = token.slice(1, separator);
      const path = token.slice(separator + 2, -1);
      const destination = new URL(path, baseURL);
      if (
        destination.protocol === "https:" ||
        destination.origin === location.origin
      ) {
        const anchor = element("a", "", label);
        anchor.href = destination.href;
        anchor.target = "_blank";
        anchor.rel = "noopener noreferrer";
        parent.append(anchor);
      } else {
        parent.append(document.createTextNode(label));
      }
    }
    position = match.index + token.length;
  }
  parent.append(document.createTextNode(source.slice(position)));
}

function renderMarkdown(source, baseURL) {
  const fragment = document.createDocumentFragment();
  const lines = source.replace(/\r\n?/g, "\n").split("\n");
  let paragraph = [];
  let list = null;
  let code = null;
  let table = null;
  function flushParagraph() {
    if (!paragraph.length) return;
    const node = element("p");
    appendInline(node, paragraph.join(" "), baseURL);
    fragment.append(node);
    paragraph = [];
  }
  for (const line of lines) {
    if (line.startsWith("```")) {
      flushParagraph();
      list = null;
      table = null;
      if (code) {
        code = null;
      } else {
        const pre = element("pre");
        code = element("code");
        pre.append(code);
        fragment.append(pre);
      }
      continue;
    }
    if (code) {
      code.textContent += `${line}\n`;
      continue;
    }
    if (!line.trim()) {
      flushParagraph();
      list = null;
      table = null;
      continue;
    }
    const heading = /^(#{1,3})\s+(.+)$/.exec(line);
    if (heading) {
      flushParagraph();
      list = null;
      table = null;
      const node = element(`h${Math.min(heading[1].length + 1, 4)}`);
      appendInline(node, heading[2], baseURL);
      fragment.append(node);
      continue;
    }
    if (line.startsWith("|")) {
      flushParagraph();
      list = null;
      if (/^\|[\s:|-]+\|$/.test(line)) continue;
      if (!table) {
        table = element("table");
        fragment.append(table);
      }
      const row = element("tr");
      for (const cell of line.slice(1, -1).split("|")) {
        const node = element("td");
        appendInline(node, cell.trim(), baseURL);
        row.append(node);
      }
      table.append(row);
      continue;
    }
    table = null;
    const bullet = /^[-*]\s+(.+)$/.exec(line);
    if (bullet) {
      flushParagraph();
      if (!list) {
        list = element("ul");
        fragment.append(list);
      }
      const item = element("li");
      appendInline(item, bullet[1], baseURL);
      list.append(item);
      continue;
    }
    list = null;
    paragraph.push(line.trim());
  }
  flushParagraph();
  return fragment;
}

function rawGitHubURL(value) {
  try {
    const url = new URL(value);
    const parts = url.pathname.split("/").filter(Boolean);
    if (
      url.protocol !== "https:" ||
      url.hostname !== "github.com" ||
      parts.length < 5 ||
      parts[2] !== "blob" ||
      !parts.every((part) => /^[a-zA-Z0-9._-]+$/.test(part))
    )
      return null;
    return `https://raw.githubusercontent.com/${parts.join("/").replace("/blob/", "/")}`;
  } catch {
    return null;
  }
}

async function showDocument(title, fetchURL, sourceURL, markdown) {
  const request = ++documentRequest;
  documentTitle.textContent = title;
  documentContent.replaceChildren(element("p", "", "読み込み中…"));
  documentSource.href = sourceURL;
  dialog.showModal();
  try {
    const response = await fetch(fetchURL);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const body = await response.text();
    if (request !== documentRequest) return;
    documentContent.replaceChildren(
      markdown
        ? renderMarkdown(body, fetchURL)
        : element("pre", "license-text", body),
    );
  } catch {
    if (request === documentRequest) {
      documentContent.replaceChildren(
        element(
          "p",
          "",
          "本文を読み込めませんでした。元のファイルを開いて確認してください。",
        ),
      );
    }
  }
}

document
  .querySelector("#document-close")
  .addEventListener("click", () => dialog.close());
document
  .querySelector("#document-done")
  .addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target === dialog) dialog.close();
});

function card(module) {
  const item = element("article", "module");
  const info = element("div", "module-info");
  const badges = element("div", "badges");
  for (const kind of module.kinds)
    badges.append(element("span", "badge", kind.toUpperCase()));
  info.append(element("h2", "", module.displayName), badges);
  if (module.limitations.length)
    info.append(element("p", "detail", module.limitations[0]));
  const artifact =
    module.artifacts.find(
      (entry) =>
        entry.architectures.includes("arm64") &&
        entry.architectures.includes("x86_64"),
    ) ?? module.artifacts[0];
  const availability = artifact
    ? `macOS ${artifact.minimumOS}以降 · ${artifact.version} r${artifact.revision} · ${(artifact.size / 1048576).toFixed(1)} MB`
    : module.availability === "instructions-only"
      ? "導入手順のみ"
      : "ダウンロードなし";
  info.append(element("p", "meta", availability));
  const credit = element("p", "credit", `${module.upstream.author} · `);
  const licenseURL = rawGitHubURL(module.licenseURL);
  if (licenseURL) {
    const license = element("button", "text-link", module.license);
    license.type = "button";
    license.addEventListener("click", () =>
      showDocument(
        `${module.displayName} のライセンス`,
        licenseURL,
        module.licenseURL,
        false,
      ),
    );
    credit.append(license);
  } else {
    credit.append(module.license);
  }
  info.append(credit);
  const sources = element("p", "source-links");
  const original = externalLink(
    "原作",
    module.originalURL ||
      (module.origin === "upstream-port" ||
      module.upstream.author !== "opera7133"
        ? module.upstream.url
        : null),
  );
  const implementation = externalLink(
    "macOS版のソース",
    module.origin === "independent"
      ? "https://github.com/opera7133/utatane-modules/tree/main/native"
      : null,
  );
  if (original) sources.append(original);
  if (implementation) sources.append(implementation);
  if (sources.childNodes.length) info.append(sources);
  const actions = element("div", "actions");
  if (artifact) {
    const download = link("ダウンロード", artifact.path, "action");
    if (download) {
      download.download = "";
      actions.append(download);
    }
  }
  if (safePath(module.instructions)) {
    const instructions = element("button", "text-link secondary", "導入手順");
    instructions.type = "button";
    instructions.addEventListener("click", () => {
      const url = new URL(`./${module.instructions}`, location.href).href;
      showDocument(`${module.displayName} の導入手順`, url, url, true);
    });
    actions.append(instructions);
  }
  item.append(info, actions);
  return item;
}

function render() {
  const term = search.value.trim().toLocaleLowerCase("ja");
  const matching = modules.filter(
    (module) =>
      (selectedKind === "all" || module.kinds.includes(selectedKind)) &&
      `${module.displayName} ${module.id} ${module.upstream.author}`
        .toLocaleLowerCase("ja")
        .includes(term),
  );
  container.replaceChildren(...matching.map(card));
  if (!matching.length)
    container.append(element("p", "empty", "該当するモジュールはありません。"));
  count.textContent = `${matching.length}件`;
}

search.addEventListener("input", render);
for (const button of filters) {
  button.addEventListener("click", () => {
    selectedKind = button.dataset.kind;
    for (const filter of filters)
      filter.setAttribute("aria-pressed", String(filter === button));
    render();
  });
}

fetch("./index.json", { cache: "no-store" })
  .then((response) => {
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  })
  .then((catalog) => {
    if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.modules))
      throw new Error("Invalid catalog");
    if (catalog.channel !== "stable")
      channel.textContent = "検証用の一覧です。正式配布版ではありません。";
    modules = catalog.modules;
    render();
  })
  .catch(() => {
    count.textContent = "カタログを読み込めませんでした。";
  });
