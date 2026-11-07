// Установщик NorkaOS: пять экранов, данные о дисках и установку даёт сторона Rust
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);
const pages = ["hello", "disk", "user", "confirm", "install"];
const MIN_FREE = 25 * 1024 ** 3;
const locales = { en: "en_US.UTF-8", ru: "ru_RU.UTF-8", uk: "uk_UA.UTF-8", pl: "pl_PL.UTF-8" };

let strings = {};
let disks = [];
let picked = null;

function t(key, ...args) {
  let s = strings[key] ?? key;
  args.forEach((a, i) => { s = s.replace(`%${i + 1}`, a); });
  return s;
}

function size(bytes) {
  const gb = bytes / 1024 ** 3;
  return gb >= 1000 ? `${(gb / 1024).toFixed(1)} TB` : `${Math.round(gb)} GB`;
}

async function setLanguage(lang) {
  strings = await (await fetch(`i18n/${lang}.json`)).json();
  document.documentElement.lang = lang;
  document.querySelectorAll("[data-t]").forEach((el) => { el.textContent = t(el.dataset.t); });
  renderDisks();
}

function show(name) {
  if (name === "confirm") renderSummary();
  document.querySelectorAll(".page").forEach((p) => p.classList.toggle("shown", p.id === name));
  // Фокус сразу в первое поле экрана: с клавиатуры не нужно искать, куда печатать
  const first = $(name).querySelector("input:not([type=radio]), select, .disk:not(:disabled), button.primary:not(:disabled)");
  first?.focus();
  const index = pages.indexOf(name);
  document.querySelectorAll("#dots li").forEach((dot, i) => {
    dot.classList.toggle("done", i < index);
    dot.classList.toggle("now", i === index);
  });
}

function mode() {
  return document.querySelector("input[name=mode]:checked").value;
}

function renderDisks() {
  const list = $("disks");
  list.innerHTML = "";
  if (!disks.length) {
    list.innerHTML = `<p>${t("no_disks")}</p>`;
  }
  for (const disk of disks) {
    const row = document.createElement("button");
    row.className = "disk" + (picked === disk ? " picked" : "");
    row.disabled = disk.live;
    const what = disk.partitions.length
      ? disk.partitions.map((p) => p.label || p.fstype || "?").join(", ")
      : t("empty_disk");
    row.innerHTML = `<div><b></b><small></small></div><span class="size"></span>`;
    row.querySelector("b").textContent = `${disk.model || disk.path} (${disk.path})`;
    row.querySelector("small").textContent = disk.live ? t("disk_live") : what;
    row.querySelector(".size").textContent = size(disk.size);
    row.onclick = () => { picked = disk; renderDisks(); $("disks").querySelector(".picked")?.focus(); };
    list.appendChild(row);
  }
  updateDisk();
}

function updateDisk() {
  const free = document.querySelector("input[name=mode][value=free]");
  const freeOk = picked && picked.gpt && picked.largest_free >= MIN_FREE;
  free.closest(".mode").classList.toggle("off", !freeOk);
  if (!freeOk && free.checked) document.querySelector("input[name=mode][value=whole]").checked = true;
  $("free-hint").textContent = !picked ? t("mode_free_hint")
    : !picked.gpt && picked.partitions.length ? t("free_mbr")
    : freeOk ? `${t("mode_free_hint")} ${t("free_space", size(picked.largest_free))}`
    : t("free_none");

  const warnings = $("disk-warnings");
  warnings.innerHTML = "";
  if (picked?.bitlocker) warnings.innerHTML += `<div class="warn">${t("warn_bitlocker")}</div>`;
  else if (picked?.windows) warnings.innerHTML += `<div class="warn">${t("warn_windows")}</div>`;
  $("disk-next").disabled = !picked;
}

function userValid() {
  const ok = /^[a-z_][a-z0-9_-]{0,31}$/.test($("username").value)
    && $("password").value.length > 0
    && $("password").value === $("password2").value
    && /^[a-zA-Z0-9-]{1,63}$/.test($("hostname").value);
  $("mismatch").hidden = !$("password2").value || $("password").value === $("password2").value;
  $("user-next").disabled = !ok;
}

function renderSummary() {
  const box = $("summary");
  box.innerHTML = "";
  const head = document.createElement("p");
  if (mode() === "whole") {
    head.textContent = t("confirm_erase", `${picked.model || ""} ${picked.path}`.trim());
    box.appendChild(head);
    const items = document.createElement("ul");
    for (const p of picked.partitions) {
      const li = document.createElement("li");
      li.textContent = `${p.path}: ${p.label || p.fstype || "?"}, ${size(p.size)}`;
      items.appendChild(li);
    }
    if (!picked.partitions.length) items.innerHTML = `<li>${t("empty_disk")}</li>`;
    box.appendChild(items);
  } else {
    head.textContent = t("confirm_free", size(picked.largest_free), picked.path);
    box.appendChild(head);
  }
  const who = document.createElement("p");
  who.textContent = t("confirm_user", `${$("fullname").value || $("username").value} (${$("username").value})`);
  box.appendChild(who);
  $("agree").checked = false;
  $("install").disabled = true;
}

async function install() {
  show("install");
  await invoke("start_install", {
    request: {
      mode: mode(),
      disk: picked.path,
      user: $("username").value,
      fullname: $("fullname").value,
      password: $("password").value,
      hostname: $("hostname").value,
      timezone: $("timezone").value,
      locale: locales[$("language").value],
    },
  });
}

listen("install", ({ payload }) => {
  if (payload.kind === "step") $("step").textContent = (strings.steps || [])[payload.value - 1] || payload.text;
  if (payload.kind === "progress") $("bar").style.width = `${payload.value}%`;
  if (payload.kind === "done") {
    $("bar").style.width = "100%";
    $("install-title").textContent = t("done_title");
    $("install-text").textContent = t("done_text");
    $("step").textContent = "";
    $("restart").hidden = false;
  }
  if (payload.kind === "failed") {
    $("install-title").textContent = t("failed_title");
    $("install-text").textContent = t("failed_text");
    $("details").textContent = payload.text;
    $("details").hidden = false;
  }
});

document.querySelectorAll("[data-go]").forEach((b) => { b.onclick = () => show(b.dataset.go); });
document.querySelectorAll("input[name=mode]").forEach((r) => { r.onchange = updateDisk; });
["username", "password", "password2", "hostname"].forEach((id) => { $(id).oninput = userValid; });
$("fullname").oninput = () => {
  // Логин подсказываем из имени, пока его не правили руками
  if (!$("username").dataset.touched) {
    $("username").value = $("fullname").value.toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 32);
  }
  userValid();
};
$("username").addEventListener("input", () => { $("username").dataset.touched = "1"; });
$("agree").onchange = () => { $("install").disabled = !$("agree").checked; };
$("install").onclick = install;
$("restart").onclick = () => invoke("reboot");
$("language").onchange = () => setLanguage($("language").value);

(async () => {
  const lang = Object.keys(locales).find((l) => navigator.language.startsWith(l)) || "en";
  $("language").value = lang;
  await setLanguage(lang);
  disks = await invoke("list_disks");
  renderDisks();
  const zones = await invoke("list_timezones");
  $("timezone").innerHTML = zones.map((z) => `<option>${z}</option>`).join("");
  $("timezone").value = zones.includes("Europe/Moscow") ? "Europe/Moscow" : "UTC";
  userValid();
  show("hello");
})();
