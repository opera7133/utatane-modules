const container = document.querySelector("#modules");
const count = document.querySelector("#count");
const channel = document.querySelector("#channel");
const search = document.querySelector("#search");
const filters = [...document.querySelectorAll("[data-kind]")];
let modules = [];
let selectedKind = "all";

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
  if (
    typeof module.licenseURL === "string" &&
    module.licenseURL.startsWith("https://")
  ) {
    const license = element("a", "", module.license);
    license.href = module.licenseURL;
    credit.append(license);
  } else {
    credit.append(module.license);
  }
  info.append(credit);
  const actions = element("div", "actions");
  if (artifact) {
    const download = link("ダウンロード", artifact.path, "action");
    if (download) {
      download.download = "";
      actions.append(download);
    }
  }
  const instructions = link("導入手順", module.instructions, "secondary");
  if (instructions) actions.append(instructions);
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
