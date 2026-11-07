// Норка Центр и Норка Привет. Работа с системой на стороне Rust, здесь только экраны
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const { getCurrentWindow } = window.__TAURI__.window;

const $ = (id) => document.getElementById(id);
let strings = {};
let mode = "center";

// Программы для выбора: id совпадают с norka-apps
const APPS = [
  { id: "games", icon: "🎮", picked: true },
  { id: "prism", icon: "⛏️", picked: true },
  { id: "vesktop", icon: "💬", picked: true },
  { id: "bottles", icon: "🍷", picked: true },
  { id: "krita", icon: "🎨" },
  { id: "office", icon: "📄" },
  { id: "blender", icon: "🧊" },
  { id: "video", icon: "🎬" },
  { id: "torrent", icon: "🧲" },
];

function t(key, ...args) {
  let s = strings[key] ?? key;
  args.forEach((a, i) => { s = s.replace(`%${i + 1}`, a); });
  return s;
}

async function loadStrings() {
  const lang = ["ru", "uk", "pl"].find((l) => navigator.language.startsWith(l)) || "en";
  strings = await (await fetch(`i18n/${lang}.json`)).json();
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-t]").forEach((el) => { el.textContent = t(el.dataset.t); });
}

function show(name) {
  document.querySelectorAll(".page").forEach((p) => p.classList.toggle("shown", p.id === name));
  document.querySelectorAll("nav button").forEach((b) => b.classList.toggle("now", b.dataset.page === name));
  $(name).querySelector("button.primary:not(:disabled), input, button")?.focus();
  if (name === "snapshots") loadSnapshots();
  if (name === "panel") loadPanel();
  if (name === "norka") loadNorka();
}

async function close() {
  if (mode === "hello") await invoke("finish_hello");
  await getCurrentWindow().close();
}

// --- Программы ---

function renderApps() {
  const list = $("app-list");
  list.innerHTML = "";
  for (const app of APPS) {
    const card = document.createElement("button");
    card.className = "app" + (app.picked ? " picked" : "");
    card.innerHTML = `<span class="icon"></span><b></b><small></small>`;
    card.querySelector(".icon").textContent = app.icon;
    card.querySelector("b").textContent = t(`app_${app.id}`);
    card.querySelector("small").textContent = t(`app_${app.id}_hint`);
    card.onclick = () => { app.picked = !app.picked; renderApps(); };
    list.appendChild(card);
  }
  $("apps-install").disabled = !APPS.some((a) => a.picked);
}

async function installApps() {
  const ids = APPS.filter((a) => a.picked).map((a) => a.id);
  $("apps-install").disabled = true;
  $("apps-skip").disabled = true;
  $("app-list").querySelectorAll("button").forEach((b) => { b.disabled = true; });
  $("apps-progress").hidden = false;
  $("apps-details").hidden = true;
  $("apps-step").textContent = t("apps_auth");
  try {
    await invoke("install_apps", { ids });
  } catch (e) {
    $("apps-step").textContent = String(e);
  }
}

listen("apps", ({ payload }) => {
  if (payload.kind === "step") $("apps-step").textContent = t("apps_installing", t(`app_${payload.text}`));
  if (payload.kind === "progress") $("bar").style.width = `${payload.value}%`;
  if (payload.kind === "done" || payload.kind === "failed") {
    $("bar").style.width = "100%";
    $("apps-skip").disabled = false;
    if (payload.kind === "done") {
      $("apps-step").textContent = t("apps_done");
      if (mode === "hello") setTimeout(() => show("tips"), 1200);
    } else {
      $("apps-step").textContent = t("apps_failed");
      $("apps-details").textContent = payload.text;
      $("apps-details").hidden = false;
      $("apps-install").disabled = false;
      $("app-list").querySelectorAll("button").forEach((b) => { b.disabled = false; });
    }
  }
});

// --- Норка и панель: скрипты Plasma ---

const NORKA_STATE = `
var r = { found: false, hidden: false };
desktops().forEach(function (d) {
  d.widgets("org.norkaos.mascot").forEach(function (w) {
    r.found = true;
    w.currentConfigGroup = ["General"];
    r.hidden = String(w.readConfig("hidden", false)) == "true";
  });
});
print(JSON.stringify(r));`;

function norkaScript(changes) {
  return `
var found = false;
desktops().forEach(function (d) {
  d.widgets("org.norkaos.mascot").forEach(function (w) {
    found = true;
    w.currentConfigGroup = ["General"];
    ${changes}
    w.reloadConfig();
  });
});
if (!found) {
  var d = desktops()[0];
  var w = d.addWidget("org.norkaos.mascot");
  w.globalShortcut = "Meta+N";
}`;
}

async function loadNorka() {
  try {
    const state = JSON.parse(await invoke("plasma", { script: NORKA_STATE }));
    $("norka-shown").checked = state.found && !state.hidden;
  } catch (e) {
    $("norka-shown").checked = true;
  }
  $("terminal-hello").checked = await invoke("terminal_hello");
  $("jokes").checked = await invoke("jokes");
}

const PANEL_STATE = `
var p = panels()[0];
print(JSON.stringify(p ? { location: p.location, length: p.lengthMode, floating: p.floating } : {}));`;

async function loadPanel() {
  let state = {};
  try { state = JSON.parse(await invoke("plasma", { script: PANEL_STATE })); } catch (e) { /* Plasma недоступна */ }
  document.querySelectorAll("#panel-location button").forEach((b) => b.classList.toggle("now", b.dataset.value === state.location));
  const style = state.length === "fill" ? "bar" : "dock";
  document.querySelectorAll("#panel-style button").forEach((b) => b.classList.toggle("now", b.dataset.value === style));
  $("panel-floating").checked = !!state.floating;
}

async function setPanel(js) {
  await invoke("plasma", { script: `var p = panels()[0]; if (p) { ${js} }` });
  setTimeout(loadPanel, 300);
}

// --- Снимки ---

async function loadSnapshots() {
  const data = await invoke("snapshots");
  const list = $("snap-list");
  list.innerHTML = "";
  if (!data.snapshots.length) list.innerHTML = `<p>${t("snap_empty")}</p>`;
  for (const s of data.snapshots) {
    const row = document.createElement("div");
    row.className = "row";
    row.innerHTML = `<div><b></b><small></small></div><button></button>`;
    row.querySelector("b").textContent = `#${s.number} · ${s.date}`;
    row.querySelector("small").textContent = s.description;
    const button = row.querySelector("button");
    button.textContent = t("snap_rollback");
    button.onclick = async () => {
      if (!confirm(t("snap_confirm", s.number))) return;
      try {
        await invoke("rollback", { number: s.number });
        $("snap-result").textContent = t("snap_rolled");
        if (confirm(t("snap_reboot"))) invoke("reboot");
      } catch (e) {
        $("snap-result").textContent = String(e);
      }
    };
    list.appendChild(row);
  }
  $("broken").hidden = !data.broken.length;
}

// --- Запуск ---

document.querySelectorAll("nav button").forEach((b) => { b.onclick = () => show(b.dataset.page); });
document.querySelectorAll("[data-go]").forEach((b) => { b.onclick = () => show(b.dataset.go); });
document.querySelectorAll("[data-action=skip]").forEach((b) => { b.onclick = () => (mode === "hello" ? show("tips") : show("norka")); });
document.querySelectorAll("[data-action=close]").forEach((b) => { b.onclick = close; });
$("apps-install").onclick = installApps;
$("norka-shown").onchange = (e) => invoke("plasma", { script: norkaScript(`w.writeConfig("hidden", ${!e.target.checked});`) });
$("norka-corner").onclick = () => invoke("plasma", { script: norkaScript(`w.writeConfig("stickToCorner", true); w.writeConfig("hidden", false);`) }).then(loadNorka);
$("terminal-hello").onchange = (e) => invoke("set_terminal_hello", { on: e.target.checked });
$("jokes").onchange = (e) => invoke("set_jokes", { on: e.target.checked });
document.querySelectorAll("#panel-location button").forEach((b) => { b.onclick = () => setPanel(`p.location = "${b.dataset.value}";`); });
document.querySelectorAll("#panel-style button").forEach((b) => {
  b.onclick = () => setPanel(b.dataset.value === "bar"
    ? `p.lengthMode = "fill"; p.alignment = "left";`
    : `p.lengthMode = "fit"; p.alignment = "center";`);
});
$("panel-floating").onchange = (e) => setPanel(`p.floating = ${e.target.checked};`);
$("clean-broken").onclick = async () => {
  try {
    await invoke("clean_broken");
    $("snap-result").textContent = t("snap_cleaned");
    loadSnapshots();
  } catch (e) {
    $("snap-result").textContent = String(e);
  }
};

(async () => {
  mode = await invoke("mode");
  await loadStrings();
  if (await invoke("needs_nvidia")) APPS.unshift({ id: "nvidia", icon: "🟩", picked: true });
  renderApps();
  $("about-version").textContent = t("about_version", await invoke("version"));
  if (mode === "hello") {
    document.body.classList.add("hello-mode");
    show("hello");
  } else {
    $("apps-skip").hidden = true;
    show("norka");
  }
})();
