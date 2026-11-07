// Норка-помощник: Norka Helper (модели) и чат. Общие $, t, invoke, listen, mode берутся из app.js
const PROMPT = `You are Norka, the mascot and helper of NorkaOS, a cozy furry Linux system based on Arch with KDE Plasma.
You are a shy, kind anthropomorphic rat boy in an oversized purple hoodie with a little bell on your collar.
You talk warmly, briefly and informally, like a friend (in Russian and Ukrainian use "ты", never "вы"), sometimes with a small rat joke. Never rude, never 18+.
You help people with their computer and explain things simply, especially to people coming from Windows.
Facts about NorkaOS: the Meta key opens the menu; Norka Center has settings for you, the panel, programs and snapshots;
before every update a snapshot is taken and can be picked in the boot menu or in Norka Center to go back;
the command "norka update" (without sudo, it asks for the password itself) updates everything; .exe files open with Wine on double click;
programs are installed in Norka Center → Programs or in Discover.
You run fully locally on this computer, nothing is sent to the internet.
If you are not sure, say so honestly. Never suggest dangerous commands (rm -rf, dd, formatting disks) without a clear warning.
Always answer in %LANG%.`;
const LANG_NAMES = { en: "English", ru: "Russian", uk: "Ukrainian", pl: "Polish" };

// Библиотека: от крошечной для слабых ПК до умной для видеокарты от 8 ГБ
const MODELS = [
  { id: "tiny", base: "qwen3:0.6b", size: 0.5, ram: 2, vram: 0, think: false },
  { id: "light", base: "qwen3:1.7b", size: 1.4, ram: 4, vram: 0, think: false },
  { id: "medium", base: "gemma3:4b", size: 3.3, ram: 8, vram: 4 },
  { id: "smart", base: "qwen3:8b", size: 5.2, ram: 16, vram: 8, think: false },
];

let aiStatus = { installed: false, running: false, models: [] };
let hardware = { ram_gb: 0, vram_gb: 0 };
let defaultModel = "";
const pulling = new Set();

const fits = (m) => hardware.vram_gb >= (m.vram || 99) || hardware.ram_gb >= m.ram;
const norkaName = (m) => `norka-${m.id}`;
const has = (m) => aiStatus.models.some((n) => n.startsWith(`${norkaName(m)}:`) || n === norkaName(m));

async function loadHelper() {
  [aiStatus, hardware, defaultModel] = await Promise.all([invoke("ai_status"), invoke("ai_hardware"), invoke("ai_default_model")]);
  $("engine").hidden = aiStatus.installed;
  $("hardware").textContent = t("hardware", hardware.ram_gb.toFixed(0), hardware.vram_gb ? hardware.vram_gb.toFixed(0) : "—");
  const recommended = [...MODELS].reverse().find(fits) || MODELS[0];
  const list = $("models");
  list.innerHTML = "";
  for (const m of MODELS) {
    const row = document.createElement("div");
    row.className = "model" + (defaultModel === norkaName(m) ? " default" : "");
    row.innerHTML = `<div><b></b><span class="tag" hidden></span><small></small></div><div class="actions"></div><div class="mini" hidden><div></div></div>`;
    row.querySelector("b").textContent = t(`model_${m.id}`);
    const tag = row.querySelector(".tag");
    if (m === recommended) { tag.hidden = false; tag.textContent = t("recommended"); }
    row.querySelector("small").textContent = `${t(`model_${m.id}_hint`)} · ${m.size} GB · ${m.base}`;
    const actions = row.querySelector(".actions");
    const button = (key, cls, onclick) => {
      const b = document.createElement("button");
      b.textContent = t(key); if (cls) b.className = cls; b.onclick = onclick; actions.appendChild(b); return b;
    };
    if (pulling.has(m.id)) {
      row.querySelector(".mini").hidden = false;
      button("downloading", "", null).disabled = true;
    } else if (has(m)) {
      if (defaultModel !== norkaName(m)) button("make_default", "", async () => { await invoke("ai_set_default_model", { model: norkaName(m) }); loadHelper(); });
      else button("is_default", "", null).disabled = true;
      button("delete", "", async () => {
        if (!confirm(t("delete_confirm", t(`model_${m.id}`)))) return;
        await invoke("ai_delete", { id: m.id, base: m.base });
        if (defaultModel === norkaName(m)) await invoke("ai_set_default_model", { model: "" });
        loadHelper();
      });
    } else {
      const b = button("download", m === recommended ? "primary" : "", () => pull(m));
      b.disabled = !aiStatus.running;
    }
    row.dataset.id = m.id;
    list.appendChild(row);
  }
  $("open-chat").disabled = !aiStatus.models.some((n) => n.startsWith("norka-"));
}

async function pull(m) {
  pulling.add(m.id);
  loadHelper();
  const lang = LANG_NAMES[document.documentElement.lang] || "English";
  await invoke("ai_pull", { id: m.id, base: m.base, system: PROMPT.replace("%LANG%", lang) });
}

listen("ai-pull", async ({ payload }) => {
  const row = document.querySelector(`.model[data-id="${payload.id}"]`);
  if (payload.kind === "progress" && row && payload.total) {
    row.querySelector(".mini").hidden = false;
    row.querySelector(".mini div").style.width = `${(100 * payload.completed) / payload.total}%`;
  }
  if (payload.kind === "done" || payload.kind === "failed") {
    pulling.delete(payload.id);
    if (payload.kind === "failed") alert(t("download_failed", payload.text));
    else if (!(await invoke("ai_default_model"))) await invoke("ai_set_default_model", { model: `norka-${payload.id}` });
    loadHelper();
  }
});

// Движок ставится через тот же norka-apps, что и программы
$("engine-install").onclick = async () => {
  $("engine-install").disabled = true;
  $("engine-step").textContent = t("apps_auth");
  try { await invoke("install_apps", { ids: ["ai"] }); } catch (e) { $("engine-step").textContent = String(e); }
};
listen("apps", ({ payload }) => {
  if (mode !== "helper" && !$("helper").classList.contains("shown")) return;
  if (payload.kind === "step") $("engine-step").textContent = t("engine_installing");
  if (payload.kind === "done") { $("engine-step").textContent = ""; setTimeout(loadHelper, 2000); }
  if (payload.kind === "failed") { $("engine-step").textContent = t("apps_failed"); $("engine-install").disabled = false; }
});

$("open-chat").onclick = () => invoke("open_chat");

// --- Чат ---

const history = [];
let chatModel = "";
let answering = null;

function bubble(kind, text) {
  const div = document.createElement("div");
  div.className = `msg ${kind}`;
  div.textContent = text;
  $("messages").appendChild(div);
  $("messages").scrollTop = $("messages").scrollHeight;
  return div;
}

async function loadChat() {
  aiStatus = await invoke("ai_status");
  const saved = await invoke("ai_default_model");
  const available = aiStatus.models.filter((n) => n.startsWith("norka-"));
  chatModel = available.find((n) => n === saved || n.startsWith(`${saved}:`)) || available[0] || "";
  const ready = aiStatus.running && chatModel;
  $("chat-empty").textContent = !aiStatus.installed || !chatModel ? t("chat_no_model") : !aiStatus.running ? t("chat_not_running") : "";
  $("chat-empty").hidden = !!ready;
  $("chat-input").disabled = !ready;
  $("chat-send").disabled = !ready;
  $("chat-input").placeholder = t("chat_placeholder");
  if (ready && !history.length) bubble("norka", t("chat_hello"));
  if (ready) $("chat-input").focus();
}

$("chat-form").onsubmit = async (e) => {
  e.preventDefault();
  const text = $("chat-input").value.trim();
  if (!text || answering) return;
  $("chat-input").value = "";
  bubble("user", text);
  history.push({ role: "user", content: text });
  answering = bubble("norka thinking", "");
  $("chat-send").disabled = true;
  const base = MODELS.find((m) => chatModel.startsWith(norkaName(m)));
  try {
    await invoke("ai_chat", { model: chatModel, messages: history, think: base && "think" in base ? base.think : null });
  } catch (err) {
    finishAnswer("error", String(err));
  }
};

$("chat-input").addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); $("chat-form").requestSubmit(); }
});

function finishAnswer(kind, text) {
  if (!answering) return;
  answering.classList.remove("thinking");
  if (kind === "error") { answering.className = "msg error"; answering.textContent = t("chat_error", text); }
  else history.push({ role: "assistant", content: answering.textContent });
  answering = null;
  $("chat-send").disabled = false;
  $("chat-input").focus();
}

listen("ai-chat", ({ payload }) => {
  if (!answering) return;
  if (payload.kind === "token") {
    answering.classList.remove("thinking");
    answering.textContent += payload.text;
    $("messages").scrollTop = $("messages").scrollHeight;
  }
  if (payload.kind === "done") finishAnswer("done", "");
  if (payload.kind === "error") finishAnswer("error", payload.text);
});
