export const learningAdminCss = String.raw`
:root {
  font-family:
    "Avenir Next",
    "PingFang SC",
    -apple-system,
    sans-serif;
  color: #182e4a;
  background: #f5f7fa;
  font-size: 15px;
  --blue: #2869cb;
  --muted: #5b6d83;
  --line: #dbe2ec;
  --green: #138577;
  --red: #b74742;
}
* {
  box-sizing: border-box;
}
[hidden] {
  display: none !important;
}
body {
  margin: 0;
}
button,
input,
select,
textarea {
  font: inherit;
}
button,
a,
input,
select,
textarea {
  outline-offset: 4px;
}
button:focus-visible,
a:focus-visible {
  outline: 3px solid #2869cb;
}
button {
  cursor: pointer;
  border: 1px solid #c7d2e1;
  background: white;
  color: #233e60;
  border-radius: 8px;
  padding: 9px 13px;
  min-height: 40px;
}
button:hover {
  background: #eef4ff;
}
button:disabled {
  opacity: 0.48;
  cursor: not-allowed;
}
button.primary {
  background: var(--blue);
  border-color: var(--blue);
  color: white;
}
button.danger {
  color: var(--red);
  border-color: #e0b4b2;
}
a {
  color: var(--blue);
  text-decoration: none;
}
a:hover {
  text-decoration: underline;
}
.top {
  height: 74px;
  background: white;
  border-bottom: 1px solid var(--line);
  padding: 0 max(24px, calc((100vw - 1500px) / 2));
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
}
.brand {
  color: #182e4a;
  font-weight: 750;
  font-size: 20px;
  white-space: nowrap;
}
.brand span {
  margin-left: 18px;
  font-size: 13px;
  font-weight: 500;
  color: var(--muted);
}
nav {
  display: flex;
  align-items: center;
  gap: 12px;
}
main {
  max-width: 1500px;
  padding: 32px 24px 60px;
  margin: auto;
}
.heading {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}
.heading h1 {
  font-size: 32px;
  letter-spacing: -0.04em;
  margin: 0;
}
.heading p {
  color: var(--muted);
  margin: 8px 0 0;
}
.connection {
  color: var(--green);
  font-size: 13px;
}
.workspace {
  display: grid;
  grid-template-columns: 310px minmax(0, 1fr);
  gap: 24px;
  align-items: start;
}
.library {
  position: sticky;
  top: 20px;
  max-height: calc(100vh - 40px);
  overflow: auto;
  background: #eef2f7;
  border-radius: 14px;
  padding: 16px;
}
.switcher {
  display: flex;
  gap: 4px;
}
.switcher button {
  flex: 1;
  border: 0;
  background: transparent;
}
.selected {
  color: var(--blue) !important;
  background: #e0ebff !important;
  font-weight: 700;
}
.filters {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 20px;
}
.filters label {
  min-width: 110px;
  flex: 1;
}
.filters label[hidden] {
  display: none;
}
label {
  display: grid;
  gap: 7px;
  font-size: 13px;
  font-weight: 600;
}
input,
select,
textarea {
  width: 100%;
  background: white;
  border: 1px solid #c7d2e1;
  border-radius: 7px;
  padding: 9px 11px;
  color: #182e4a;
  line-height: 1.55;
}
input:focus,
textarea:focus,
select:focus {
  outline: 2px solid #2869cb55;
  border-color: var(--blue);
}
textarea {
  resize: vertical;
  min-height: 64px;
}
input[type="checkbox"],
input[type="radio"] {
  width: 18px;
  height: 18px;
  min-height: 18px;
  accent-color: var(--blue);
}
.muted {
  color: var(--muted);
  font-size: 13px;
}
.item {
  display: block;
  width: 100%;
  text-align: left;
  margin-bottom: 8px;
  border: 1px solid transparent;
  border-left: 3px solid transparent;
  background: transparent;
  padding: 14px 12px;
  border-radius: 6px;
}
.item:hover {
  background: white;
}
.item.active {
  border-color: #b6cdee;
  border-left-color: var(--blue);
  background: white;
}
.item strong {
  display: block;
  line-height: 1.45;
  margin-bottom: 7px;
}
.item small {
  display: block;
  color: var(--muted);
  line-height: 1.7;
}
.item .badge {
  margin-top: 7px;
}
.badge {
  display: inline-block;
  background: #e8eef6;
  color: #3c597c;
  border-radius: 5px;
  font-size: 12px;
  padding: 4px 7px;
}
.badge.review,
.badge.published {
  color: #086b5e;
  background: #e0f2ee;
}
.badge.failed {
  color: #973f3b;
  background: #fae6e4;
}
.pager {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 18px;
  font-size: 12px;
}
.pager button {
  padding: 7px 10px;
  font-size: 12px;
}
.detail {
  background: white;
  border: 1px solid var(--line);
  border-radius: 14px;
  min-height: 570px;
  overflow: hidden;
}
.empty {
  padding: 100px 30px;
  text-align: center;
  color: var(--muted);
}
.empty h2 {
  color: #182e4a;
  font-size: 24px;
}
.book-mark {
  font-size: 44px;
  color: #70a2d7;
}
article#document {
  padding: 30px;
}
.document-head {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 20px;
}
.document-head h2 {
  margin: 12px 0 6px;
  font-size: 27px;
  line-height: 1.4;
}
.document-head p {
  overflow-wrap: anywhere;
}
.document-head label {
  min-width: 90px;
}
.state-hint {
  font-size: 13px;
  line-height: 1.65;
  background: #f1f5fb;
  border-left: 3px solid #a2bcdf;
  padding: 11px 14px;
  margin: 22px 0;
}
.mode-switch {
  display: flex;
  border-bottom: 1px solid var(--line);
  gap: 4px;
  margin-bottom: 24px;
  padding-bottom: 10px;
}
.mode-switch button {
  border: 0;
  background: transparent;
}
.lead {
  line-height: 1.8;
  max-width: 74ch;
}
.scene {
  color: #47617e;
  border-left: 3px solid #b3cbe6;
  padding: 3px 16px;
  margin: 20px 0 28px;
  line-height: 1.75;
}
.beat {
  display: grid;
  grid-template-columns: 80px 1fr;
  gap: 16px;
  background: #f3f7fb;
  padding: 18px;
  margin: 18px 0;
  border-radius: 8px;
}
.beat b {
  font-size: 13px;
  color: #47617e;
}
.beat p {
  margin: 0 0 6px;
  line-height: 1.7;
}
.beat small {
  color: var(--muted);
  line-height: 1.65;
}
.question {
  padding: 22px 0;
  border-bottom: 1px solid var(--line);
}
.question h3 {
  font-size: 15px;
  color: var(--muted);
  font-weight: 600;
  margin: 0 0 14px;
}
.prompt {
  font-size: 18px;
  line-height: 1.8;
  white-space: pre-line;
}
.instruction {
  font-size: 13px;
  color: var(--muted);
}
.option {
  border: 1px solid var(--line);
  padding: 10px 14px;
  border-radius: 7px;
  margin: 8px 0;
  white-space: pre-line;
}
.tokens {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  margin: 15px 0;
}
.token {
  padding: 8px 12px;
  border-radius: 6px;
  background: #edf2fa;
}
.pairs {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.hint {
  margin-top: 15px;
  color: #546b87;
  font-size: 13px;
  line-height: 1.8;
}
details {
  margin-top: 14px;
}
summary {
  cursor: pointer;
  font-size: 13px;
  color: var(--blue);
  padding: 7px 0;
}
details p {
  font-size: 14px;
  line-height: 1.85;
  white-space: pre-line;
}
.answer {
  color: var(--green);
  font-weight: 650;
}
.editor-note {
  font-size: 13px;
  color: var(--muted);
}
fieldset {
  border: 0;
  border-top: 1px solid var(--line);
  margin: 28px 0;
  padding: 20px 0 0;
  min-width: 0;
}
legend {
  font-size: 17px;
  font-weight: 700;
  padding-right: 14px;
}
.form-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}
.form-grid .wide {
  grid-column: 1/-1;
}
.edit-option {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 10px 0;
}
.edit-option input[type="text"] {
  flex: 1;
}
.edit-option span {
  font-size: 12px;
  color: var(--muted);
  min-width: 28px;
}
.edit-option label {
  display: flex;
  align-items: center;
  white-space: nowrap;
}
.actions {
  background: #f5f8fc;
  padding: 22px;
  border-radius: 9px;
  margin-top: 30px;
}
.actions h3 {
  margin: 0 0 18px;
  font-size: 17px;
}
.confirmation {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 18px 0;
  line-height: 1.6;
  font-weight: 500;
}
.action-buttons {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  margin-top: 16px;
}
#notice:empty {
  display: none;
}
#notice {
  padding: 13px 18px;
  background: #e4efff;
  border-radius: 8px;
  margin-bottom: 18px;
  line-height: 1.65;
}
#notice.error {
  color: #923b36;
  background: #fbe9e7;
}
.audit-entry {
  padding: 18px 0;
  border-bottom: 1px solid var(--line);
}
.audit-entry h3 {
  font-size: 16px;
}
.audit-entry p {
  font-size: 13px;
  line-height: 1.75;
  overflow-wrap: anywhere;
}
.checks {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.check {
  padding: 5px 8px;
  font-size: 12px;
  border-radius: 5px;
  color: #146e62;
  background: #e7f5f1;
}
.check.fail {
  color: #9b413c;
  background: #fbeae7;
}
pre {
  background: #f0f4f8;
  border-radius: 7px;
  padding: 14px;
  max-height: 360px;
  overflow: auto;
  font-size: 12px;
  line-height: 1.65;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
dialog {
  border: 1px solid var(--line);
  border-radius: 14px;
  width: min(430px, calc(100vw - 32px));
  padding: 28px;
  color: #182e4a;
}
dialog::backdrop {
  background: #182e4a77;
}
dialog h2 {
  margin: 0 0 12px;
}
dialog p {
  line-height: 1.65;
  font-size: 14px;
  color: var(--muted);
}
dialog button {
  width: 100%;
  margin-top: 15px;
}
#loginError {
  color: var(--red);
}

.media-options {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(155px, 1fr));
  gap: 12px;
  align-items: start;
}
.media-option {
  min-width: 0;
}
.media-picture {
  margin: 8px 0;
  display: grid;
  justify-items: center;
  gap: 8px;
}
.media-picture img {
  width: 100%;
  max-width: 190px;
  height: auto;
  aspect-ratio: 1;
  object-fit: contain;
  background: white;
  border: 1px solid var(--line);
  border-radius: 9px;
}
.media-picture .muted {
  font-size: 12px;
  text-align: center;
}
.media-audio {
  padding: 16px;
  margin: 16px 0;
  background: #eef4fb;
  border-left: 3px solid var(--blue);
  border-radius: 0 10px 10px 0;
}
.media-audio audio {
  display: block;
  width: 100%;
  margin: 12px 0;
}
.media-audio label {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  margin: 8px 0;
}
.media-audio select {
  width: auto;
}
.media-review {
  margin: 12px 0;
  font-size: 13px;
  overflow-wrap: anywhere;
}
.media-review summary {
  cursor: pointer;
  color: var(--blue);
}
.media-review p {
  margin: 8px 0;
  line-height: 1.7;
}
.media-review code {
  font-size: 11px;
  word-break: break-all;
}

@media (max-width: 900px) {
  main {
    padding: 22px 14px;
  }
  .workspace {
    grid-template-columns: 1fr;
  }
  .library {
    position: static;
    max-height: none;
  }
  #items {
    max-height: 300px;
    overflow: auto;
  }
  .top {
    padding: 0 16px;
  }
  .brand span {
    display: none;
  }
  article#document {
    padding: 22px;
  }
  .heading p {
    font-size: 13px;
  }
  .form-grid {
    grid-template-columns: 1fr;
  }
  .beat {
    grid-template-columns: 1fr;
    gap: 8px;
  }
}
@media (max-width: 520px) {
  nav {
    gap: 6px;
    font-size: 12px;
  }
  .top {
    height: auto;
    min-height: 68px;
    gap: 10px;
    flex-wrap: wrap;
    padding: 12px 16px;
  }
  .heading {
    align-items: flex-start;
  }
  .heading h1 {
    font-size: 28px;
  }
  .document-head {
    display: block;
  }
  .document-head label {
    margin-top: 12px;
  }
  .action-buttons button {
    width: 100%;
  }
  .mode-switch button {
    font-size: 13px;
    padding: 8px;
  }
  .edit-option {
    flex-wrap: wrap;
  }
  .pairs {
    gap: 6px;
  }
  .option {
    padding: 8px;
  }
}
`;

export const learningAdminJavascript = String.raw`
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const levels = {
    kindergarten: "幼儿启蒙",
    primary1: "小学一年级",
    primary2: "小学二年级",
    primary3: "小学三年级",
    primary4: "小学四年级",
    primary5: "小学五年级",
    primary6: "小学六年级",
    junior1: "初中一年级",
    junior2: "初中二年级",
    junior3: "初中三年级",
    senior1: "高中一年级",
    senior2: "高中二年级",
    senior3: "高中三年级",
    undergraduate: "大学",
    postgraduate: "研究生",
    advanced: "高级",
  };
  const statuses = {
    pending: "等待生成",
    running: "正在生成",
    review: "等待审核",
    failed: "未通过",
    published: "已发布",
  };
  const types = {
    choice: "选择",
    listeningChoice: "听力选择",
    arrange: "词块组句",
    completion: "填空",
    dictation: "听写",
    matching: "配对",
  };
  const errors = {
    AUTHOR_CONTENT_INVALID: "候选内容检查未通过",
    AUTHOR_REQUEST_FAILED: "作者请求失败",
    REVIEW_REQUEST_FAILED: "审题请求失败",
    INDEPENDENT_REVIEW_FAILED: "独立审题未通过",
    EDITOR_REVISED: "已有后继修订稿",
    EDITOR_REJECTED: "编辑退回",
    EDITOR_BLUEPRINT_CHANGED: "课程蓝图已变化",
    LEASE_EXHAUSTED: "任务租约已耗尽",
  };
  const state = {
    token: sessionStorage.getItem("lingotrip-admin-token") || "",
    kind: "units",
    offset: 0,
    total: 0,
    selected: null,
    detail: null,
    draft: null,
    dirty: false,
    busy: false,
    epoch: 0,
    listEpoch: 0,
    mode: "preview",
    pendingEdit: null,
  };
  function el(tag, text, cls) {
    const n = document.createElement(tag);
    if (text !== undefined) n.textContent = String(text);
    if (cls) n.className = cls;
    return n;
  }
  function badge(text, status) {
    return el("span", text, "badge " + (status || ""));
  }
  function notice(message, error = false) {
    $("notice").textContent = message;
    $("notice").className = error ? "error" : "";
  }
  function errorText(code) {
    return errors[String(code).split(":")[0]] || code || "没有失败记录";
  }
  function date(value) {
    return value ? new Date(value).toLocaleString("zh-CN") : "—";
  }
  function discard() {
    return (
      !state.dirty || window.confirm("离开会放弃尚未提交的修订，是否继续？")
    );
  }
  async function api(path, method = "GET", body, binary = false, signal) {
    const r = await fetch("/internal/admin/learning" + path, {
      method,
      signal,
      headers: {
        authorization: "Bearer " + state.token,
        ...(body ? { "content-type": "application/json" } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (r.ok && binary) return r.blob();
    const data = await r.json();
    if (!r.ok) {
      if (r.status === 401) {
        resetMedia();
        state.token = "";
        sessionStorage.removeItem("lingotrip-admin-token");
        $("connection").textContent = "连接已失效";
        if (!$("login").open) $("login").showModal();
      }
      const detail = data.error?.details || data.details;
      let message =
        (r.status === 401
          ? "管理员凭据无效，请重新连接。"
          : data.error?.message || data.message) ||
        "操作未完成，请刷新后重试。";
      if (Array.isArray(detail) && detail.length)
        message +=
          " " +
          detail
            .slice(0, 3)
            .map((i) => i.path.join(".") + "：" + i.message)
            .join("；");
      throw new Error(message);
    }
    return data;
  }
  Object.entries(levels).forEach(([value, title]) => {
    const o = el("option", title);
    o.value = value;
    $("level").append(o);
  });
  async function load() {
    const epoch = ++state.listEpoch,
      kind = state.kind;
    const q = new URLSearchParams({
      limit: "30",
      offset: String(state.offset),
    });
    for (const key of ["role", "level"])
      if ($(key).value) q.set(key, $(key).value);
    if (kind === "jobs" && $("status").value)
      q.set("status", $("status").value);
    const result = await api("/" + kind + "?" + q);
    if (epoch !== state.listEpoch) return;
    state.total = result.total;
    $("listCount").textContent = "共 " + result.total + " 项内容";
    $("pageNumber").textContent = String(Math.floor(state.offset / 30) + 1);
    $("previous").disabled = state.offset === 0;
    $("next").disabled = state.offset + 30 >= state.total;
    $("items").replaceChildren();
    for (const item of result.items) {
      const button = el(
        "button",
        undefined,
        "item" + (state.selected === item.id ? " active" : ""),
      );
      button.type = "button";
      button.append(
        el("strong", item.title || "尚未形成有效稿件"),
        el(
          "small",
          (item.role_key || "") +
            " / " +
            (levels[item.level_key] || item.level_key),
        ),
      );
      button.append(
        badge(
          kind === "units"
            ? "第 " + item.current_version + " 版 · " + item.questions + " 题"
            : item.is_revision && item.status === "pending"
              ? "等待复审"
              : statuses[item.status],
          kind === "units" ? "published" : item.status,
        ),
      );
      if (item.last_error_code)
        button.append(el("small", errorText(item.last_error_code)));
      button.addEventListener("click", () =>
        select(item.id).catch((e) => notice(e.message, true)),
      );
      $("items").append(button);
    }
    if (!result.items.length)
      $("items").append(el("p", "当前筛选下没有内容。", "muted"));
    $("connection").textContent = "已连接";
  }
  async function select(id, version) {
    if (state.busy || !discard()) return;
    resetMedia();
    const epoch = ++state.epoch;
    state.dirty = false;
    state.selected = id;
    state.detail = null;
    updateActions();
    const kind = state.kind;
    const result = await api(
      "/" +
        kind +
        "/" +
        encodeURIComponent(id) +
        (version ? "?version=" + version : ""),
    );
    if (epoch !== state.epoch || kind !== state.kind) return;
    state.detail = result;
    state.draft = structuredClone(
      kind === "units" ? result.unit : result.previewUnit,
    );
    state.mode = "preview";
    state.pendingEdit = null;
    $("notes").value = "";
    $("confirmed").checked = false;
    render();
    await load();
  }
  function showMode(mode) {
    if (mode !== "preview") stopAudio();
    state.mode = mode;
    for (const name of ["preview", "edit", "audit"]) {
      $(name === "edit" ? "editor" : name).hidden = name !== mode;
      $(name + "Mode").classList.toggle("selected", name === mode);
    }
  }
  function render() {
    const d = state.detail,
      u = state.draft;
    $("empty").hidden = true;
    $("document").hidden = false;
    $("detailTitle").textContent = u?.title || "尚未形成有效稿件";
    $("detailBadge").textContent =
      state.kind === "units"
        ? "正式单元"
        : d.isRevision && d.status === "pending"
          ? "等待复审"
          : statuses[d.status];
    $("detailBadge").className =
      "badge " + (state.kind === "units" ? "published" : d.status);
    $("detailMeta").textContent =
      (u?.roleKey || d.role_key) +
      " / " +
      (levels[u?.level || d.level_key] || "") +
      (u ? " / " + u.questions.length + " 题" : "");
    $("versionLabel").hidden = state.kind !== "units";
    $("version").replaceChildren();
    if (state.kind === "units")
      for (const v of d.versions) {
        const option = el("option", "第 " + v.version + " 版");
        option.value = v.version;
        option.selected = v.version === u.version;
        $("version").append(option);
      }
    $("stateHint").textContent =
      state.kind === "units"
        ? "已发布版本保持不变，用户已经开始的挑战始终使用对应快照。"
        : d.status === "review"
          ? "独立审题已通过。发布前仍需逐题核对答案、提示与解析。"
          : d.isRevision && d.status === "pending"
            ? "修订稿已保存，等待服务端重新独立审题；可在审核记录中追溯原稿。"
            : d.status === "running"
              ? "服务端正在处理此稿件，完成后可刷新查看结果。"
              : d.last_error_code === "EDITOR_REVISED"
                ? "已有后继修订稿。请到审核记录中打开后继修订，继续处理新稿。"
                : d.last_error_code
                  ? errorText(d.last_error_code) +
                    "。修改有效候选后可提交新的修订任务。"
                  : "候选还未通过完整审核，暂不能分配给用户。";
    $("editMode").disabled = state.kind !== "jobs" || !d.canRevise;
    renderPreview();
    renderEditor();
    renderAudit();
    showMode("preview");
    updateActions();
  }
  let mediaEpoch = 0;
  const mediaCache = new Map(),
    mediaURLs = new Set(),
    mediaRequests = new Set();
  function stopAudio() {
    for (const audio of $("preview").querySelectorAll("audio")) audio.pause();
  }
  function resetMedia() {
    mediaEpoch++;
    stopAudio();
    for (const request of mediaRequests) request.abort();
    mediaRequests.clear();
    for (const url of mediaURLs) URL.revokeObjectURL(url);
    mediaURLs.clear();
    mediaCache.clear();
  }
  async function mediaURL(kind, asset) {
    if (mediaCache.has(asset.id)) return mediaCache.get(asset.id);
    const epoch = mediaEpoch,
      controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    mediaRequests.add(controller);
    const query = new URLSearchParams({
      hash: state.detail.contentHash || state.detail.mediaHash,
    });
    if (state.kind === "units")
      query.set("version", String(state.detail.unit.version));
    const path =
      "/" +
      state.kind +
      "/" +
      encodeURIComponent(state.selected) +
      "/media/" +
      kind +
      "/" +
      asset.id +
      "?" +
      query;
    const promise = (async () => {
      const blob = await api(path, "GET", undefined, true, controller.signal);
      if (blob.size !== asset.byteSize || blob.type !== asset.contentType)
        throw new Error("素材与登记信息不一致，请刷新后重试。");
      const digest = Array.from(
        new Uint8Array(
          await crypto.subtle.digest("SHA-256", await blob.arrayBuffer()),
        ),
      )
        .map((byte) => byte.toString(16).padStart(2, "0"))
        .join("");
      if (digest !== asset.sha256)
        throw new Error("素材校验未通过，请刷新后重试。");
      if (epoch !== mediaEpoch)
        throw new DOMException("已切换内容", "AbortError");
      const url = URL.createObjectURL(blob);
      mediaURLs.add(url);
      return url;
    })();
    mediaCache.set(asset.id, promise);
    try {
      return await promise;
    } catch (error) {
      if (epoch === mediaEpoch) mediaCache.delete(asset.id);
      throw error;
    } finally {
      clearTimeout(timer);
      mediaRequests.delete(controller);
    }
  }
  function mediaReview(asset, kind) {
    const detail = el("details", undefined, "media-review");
    detail.append(el("summary", "素材来源与审核"));
    if (kind === "images")
      detail.append(
        el("p", "图意：" + asset.description),
        el("p", "来源：" + asset.source),
        el("p", "审核者：" + asset.reviewedBy),
      );
    else
      detail.append(
        el(
          "p",
          "固定声音：" +
            asset.voice +
            "；时长 " +
            (asset.durationMs / 1000).toFixed(2) +
            " 秒",
        ),
      );
    detail.append(
      el("p", "审核日期：" + asset.reviewedAt),
      el("p", asset.reviewNotes),
      el("code", "SHA-256：" + asset.sha256),
    );
    return detail;
  }
  function pictureOption(option, label) {
    const box = el("div", undefined, "option media-option");
    box.append(el("b", label));
    if (!option.imageAssetId) {
      box.append(el("p", option.text));
      return box;
    }
    const asset = state.detail.media?.images.find(
      (item) => item.id === option.imageAssetId,
    );
    if (!asset) {
      box.append(
        el("p", "图片尚未登记，当前无法预览。", "muted"),
        el("p", option.text),
      );
      return box;
    }
    const figure = el("figure", undefined, "media-picture"),
      img = el("img"),
      status = el("span", "正在载入图片…", "muted"),
      retry = el("button", "重试图片");
    img.alt = option.text;
    img.hidden = true;
    img.width = asset.width;
    img.height = asset.height;
    retry.type = "button";
    retry.hidden = true;
    figure.append(img, status, retry);
    box.append(figure, el("p", option.text), mediaReview(asset, "images"));
    const epoch = mediaEpoch;
    const load = async () => {
      if (epoch !== mediaEpoch) return;
      retry.hidden = true;
      status.hidden = false;
      status.textContent = "正在载入图片…";
      try {
        const url = await mediaURL("images", asset);
        if (epoch !== mediaEpoch) return;
        img.src = url;
        await img.decode();
        if (epoch !== mediaEpoch) return;
        img.hidden = false;
        status.hidden = true;
      } catch (error) {
        if (epoch !== mediaEpoch) return;
        status.textContent =
          error.name === "AbortError"
            ? "图片载入超时，请重试。"
            : error.message;
        retry.hidden = false;
      }
    };
    retry.addEventListener("click", load);
    void load();
    return box;
  }
  function audioPreview(question) {
    const box = el("div", undefined, "media-audio");
    box.append(el("p", "听力原文（管理员可见）：" + question.audio.text));
    const asset = state.detail.media?.audio.find(
      (item) => item.id === question.audio.assetId,
    );
    if (!asset) {
      box.append(el("p", "音频尚未登记，当前无法试听。", "muted"));
      return box;
    }
    const load = el("button", "载入并试听"),
      audio = el("audio"),
      status = el("p", "点击后读取此版本录音，不会自动播放其他题目。", "muted");
    load.type = "button";
    audio.controls = true;
    audio.preload = "none";
    audio.hidden = true;
    audio.setAttribute("aria-label", "题目 " + question.id + " 的听力录音");
    const label = el("label", "播放速度"),
      speed = el("select");
    speed.setAttribute("aria-label", "播放速度");
    for (const [value, title] of [
      ["1", "正常"],
      ["0.8", "慢速 0.8×"],
    ]) {
      const option = el("option", title);
      option.value = value;
      speed.append(option);
    }
    speed.addEventListener("change", () => {
      audio.playbackRate = Number(speed.value);
    });
    label.append(speed);
    label.hidden = true;
    audio.addEventListener("play", () => {
      for (const other of $("preview").querySelectorAll("audio"))
        if (other !== audio) other.pause();
    });
    audio.addEventListener("error", () => {
      status.textContent = "音频无法播放，请重试载入。";
      load.hidden = false;
    });
    const epoch = mediaEpoch;
    load.addEventListener("click", async () => {
      if (epoch !== mediaEpoch) return;
      load.disabled = true;
      status.textContent = "正在载入录音…";
      try {
        const url = await mediaURL("audio", asset);
        if (epoch !== mediaEpoch) return;
        audio.src = url;
        audio.hidden = false;
        label.hidden = false;
        load.hidden = true;
        audio.playbackRate = Number(speed.value);
        status.textContent = "可对照原文复核发音，也可切换慢速。";
        if (state.mode === "preview") {
          try {
            await audio.play();
          } catch {
            status.textContent = "录音已载入，点击播放器开始试听。";
          }
        } else {
          status.textContent = "录音已载入，点击播放器开始试听。";
        }
      } catch (error) {
        if (epoch !== mediaEpoch) return;
        status.textContent =
          error.name === "AbortError"
            ? "录音载入超时，请重试。"
            : error.message;
        load.textContent = "重试载入";
      } finally {
        load.disabled = false;
      }
    });
    box.append(load, audio, label, status, mediaReview(asset, "audio"));
    return box;
  }
  function renderPreview() {
    resetMedia();
    const root = $("preview");
    root.replaceChildren();
    const u = state.draft;
    if (!u) {
      root.append(
        el(
          "p",
          "本次输出没有形成有效单元，请在“审核与记录”中查看失败证据。",
          "muted",
        ),
      );
      return;
    }
    root.append(el("p", u.summary, "lead"), el("p", u.scene, "scene"));
    const beats = (after) => {
      for (const b of u.beats.filter((b) => b.afterQuestion === after)) {
        const block = el("div", undefined, "beat"),
          body = el("div");
        body.append(el("p", b.text), el("small", b.translation));
        block.append(el("b", b.speaker), body);
        root.append(block);
      }
    };
    beats(0);
    u.questions.forEach((q, i) => {
      const block = el("section", undefined, "question");
      block.append(
        el("h3", "第 " + (i + 1) + " 题 / " + types[q.type]),
        el("p", q.instruction, "instruction"),
        el("div", q.prompt, "prompt"),
      );
      if (q.audio) block.append(audioPreview(q));
      if (q.options) {
        const options = el(
          "div",
          undefined,
          q.options.some((o) => o.imageAssetId) ? "media-options" : "",
        );
        q.options.forEach((o, j) =>
          options.append(pictureOption(o, String.fromCharCode(65 + j))),
        );
        block.append(options);
      }
      if (q.tokens) {
        const tokens = el("div", undefined, "tokens");
        q.tokens.forEach((o) => tokens.append(el("span", o.text, "token")));
        block.append(tokens);
      }
      if (q.left) {
        const pairs = el("div", undefined, "pairs");
        for (const list of [q.left, q.right]) {
          const column = el("div");
          list.forEach((o, index) =>
            column.append(pictureOption(o, String(index + 1))),
          );
          pairs.append(column);
        }
        block.append(pairs);
      }

      block.append(el("p", "提示：" + q.hint, "hint"));
      const details = el("details");
      details.append(el("summary", "查看答案与解析"));
      let answer =
        q.acceptedAnswers?.join(" / ") ||
        q.options?.find((o) => o.id === q.answer)?.text;
      if (q.acceptedOrders)
        answer = q.acceptedOrders
          .map((order) =>
            order
              .map((id) => q.tokens.find((t) => t.id === id)?.text || id)
              .join(" "),
          )
          .join(" / ");
      if (q.answerPairs)
        answer = q.answerPairs
          .map(
            (p) =>
              (q.left.find((o) => o.id === p.left)?.text || p.left) +
              " → " +
              (q.right.find((o) => o.id === p.right)?.text || p.right),
          )
          .join("；");
      details.append(
        el("p", answer, "answer"),
        el("p", q.explanation),
        el(
          "p",
          "目标：" + q.goalId + "；难度依据：" + q.difficultyReason,
          "muted",
        ),
      );
      block.append(details);
      root.append(block);
      beats(i + 1);
    });
    const sources = el("details");
    sources.append(el("summary", "来源与内容审核"));
    for (const ref of u.references)
      sources.append(
        el(
          "p",
          ref.sourceId +
            " / " +
            ref.unit +
            " / " +
            ref.pages +
            "\n" +
            ref.alignment,
        ),
      );
    sources.append(
      el(
        "p",
        u.authorship.author +
          "；" +
          u.authorship.reviewedBy +
          "；" +
          u.authorship.reviewNotes,
      ),
    );
    root.append(sources);
  }
  function changed() {
    state.dirty = true;
    state.pendingEdit = null;
    $("confirmed").checked = false;
    updateActions();
  }
  function field(
    parent,
    label,
    value,
    set,
    { wide = false, lines = 2, type = "text" } = {},
  ) {
    const box = el("label", label, wide ? "wide" : "");
    const input = document.createElement(lines > 1 ? "textarea" : "input");
    if (lines > 1) input.rows = lines;
    else input.type = type;
    input.value = value;
    input.addEventListener("input", () => {
      set(type === "number" ? Number(input.value) : input.value);
      changed();
    });
    box.append(input);
    parent.append(box);
    return input;
  }
  function renderEditor() {
    const root = $("editFields");
    root.replaceChildren();
    const u = state.draft;
    if (!u || state.kind !== "jobs") return;
    const reset = el("button", "放弃未提交修改");
    reset.type = "button";
    reset.addEventListener("click", () => {
      if (!discard()) return;
      state.draft = structuredClone(state.detail.editableUnit);
      state.dirty = false;
      state.pendingEdit = null;
      renderEditor();
      renderPreview();
      updateActions();
    });
    root.append(reset);
    const meta = el("div", undefined, "form-grid");
    field(meta, "单元标题", u.title, (v) => (u.title = v), {
      wide: true,
      lines: 1,
    });
    field(meta, "单元说明", u.summary, (v) => (u.summary = v), { wide: true });
    field(meta, "开场情境", u.scene, (v) => (u.scene = v), { wide: true });
    root.append(meta);
    const story = el("fieldset");
    story.append(el("legend", "剧情演绎"));
    u.beats.forEach((b, i) => {
      const group = el("div", undefined, "form-grid");
      group.append(el("h3", "第 " + (i + 1) + " 幕", "wide"));
      field(group, "说话者", b.speaker, (v) => (b.speaker = v), { lines: 1 });
      const at = field(
        group,
        "在第几题后出现（开场为 0）",
        b.afterQuestion,
        (v) => (b.afterQuestion = v),
        { lines: 1, type: "number" },
      );
      at.min = 0;
      at.max = u.questions.length;
      field(group, "英文对白", b.text, (v) => (b.text = v));
      field(group, "中文对白", b.translation, (v) => (b.translation = v));
      story.append(group);
    });
    root.append(story);
    u.questions.forEach((q, i) => {
      const group = el("fieldset");
      group.append(el("legend", "第 " + (i + 1) + " 题 · " + types[q.type]));
      const grid = el("div", undefined, "form-grid");
      field(grid, "作答说明", q.instruction, (v) => (q.instruction = v), {
        wide: true,
        lines: 1,
      });
      field(grid, "题干与完整作答条件", q.prompt, (v) => (q.prompt = v), {
        wide: true,
        lines: 3,
      });
      field(grid, "提示（不直接给答案）", q.hint, (v) => (q.hint = v), {
        wide: true,
      });
      field(grid, "解析", q.explanation, (v) => (q.explanation = v), {
        wide: true,
        lines: 3,
      });
      field(
        grid,
        "难度依据",
        q.difficultyReason,
        (v) => (q.difficultyReason = v),
        { wide: true },
      );
      const goal = el("label", "学习目标");
      const select = el("select");
      for (const id of state.detail.allowedGoalIds) {
        const option = el("option", id);
        option.value = id;
        option.selected = id === q.goalId;
        select.append(option);
      }
      select.addEventListener("change", () => {
        q.goalId = select.value;
        u.goalIds = [...new Set(u.questions.map((x) => x.goalId))];
        changed();
      });
      goal.append(select);
      grid.append(goal);
      group.append(grid);
      if (q.options) {
        group.append(el("p", "选项与正确答案", "muted"));
        q.options.forEach((o, j) => {
          const row = el("div", undefined, "edit-option"),
            label = el("label", String.fromCharCode(65 + j)),
            radio = el("input");
          radio.type = "radio";
          radio.name = "answer-" + i;
          radio.checked = q.answer === o.id;
          radio.setAttribute(
            "aria-label",
            "将选项 " + String.fromCharCode(65 + j) + " 设为正确答案",
          );
          radio.addEventListener("change", () => {
            q.answer = o.id;
            changed();
          });
          label.prepend(radio);
          const input = el("input");
          input.type = "text";
          input.value = o.text;
          input.setAttribute(
            "aria-label",
            "选项 " + String.fromCharCode(65 + j) + " 内容",
          );
          input.addEventListener("input", () => {
            o.text = input.value;
            changed();
          });
          row.append(label, input);
          group.append(row);
        });
      }
      if (q.acceptedAnswers)
        field(
          group,
          "可接受的答案（每行一种）",
          q.acceptedAnswers.join("\n"),
          (v) =>
            (q.acceptedAnswers = v
              .split("\n")
              .map((x) => x.trim())
              .filter(Boolean)),
          { lines: 3 },
        );
      if (q.tokens) {
        q.tokens.forEach((o, j) =>
          field(group, "词块 " + (j + 1), o.text, (v) => (o.text = v), {
            lines: 1,
          }),
        );
        field(
          group,
          "正确词块顺序（用上面的编号，以空格分隔；每行一种答案）",
          q.acceptedOrders
            .map((order) =>
              order
                .map((id) => q.tokens.findIndex((t) => t.id === id) + 1)
                .join(" "),
            )
            .join("\n"),
          (v) =>
            (q.acceptedOrders = v
              .split("\n")
              .filter((x) => x.trim())
              .map((line) =>
                line
                  .trim()
                  .split(/\s+/)
                  .map((n) => q.tokens[Number(n) - 1]?.id || "__invalid__"),
              )),
          { lines: 2 },
        );
      }
      if (q.left) {
        for (const [name, list] of [
          ["左列", q.left],
          ["右列", q.right],
        ])
          list.forEach((o, j) =>
            field(group, name + " " + (j + 1), o.text, (v) => (o.text = v), {
              lines: 1,
            }),
          );
        group.append(el("p", "正确配对（左右列使用上面的编号）", "muted"));
        q.left.forEach((o, j) => {
          const label = el("label", "左列 " + (j + 1) + " 对应"),
            select = el("select");
          q.right.forEach((r, k) => {
            const option = el("option", "右列 " + (k + 1));
            option.value = r.id;
            option.selected =
              q.answerPairs.find((p) => p.left === o.id)?.right === r.id;
            select.append(option);
          });
          select.addEventListener("change", () => {
            q.answerPairs = q.answerPairs
              .filter((p) => p.left !== o.id)
              .concat({ left: o.id, right: select.value });
            changed();
          });
          label.append(select);
          group.append(label);
        });
      }
      root.append(group);
    });
  }
  function reportView(parent, report) {
    if (!report) return;
    if (report.rawResponse !== undefined) {
      const d = el("details");
      d.append(
        el("summary", "查看未通过格式检查的原始输出"),
        el("pre", report.rawResponse || "空正文"),
      );
      parent.append(d);
      return;
    }
    if (report.notes) parent.append(el("p", report.notes));
    const checks = el("div", undefined, "checks");
    for (const [key, label] of Object.entries({
      roleFits: "角色贴合",
      levelFits: "水平匹配",
      novel: "内容新颖",
      storyDoesNotLeakAnswers: "剧情不泄题",
    }))
      if (typeof report[key] === "boolean")
        checks.append(
          el(
            "span",
            label + (report[key] ? " ✓" : " ×"),
            "check" + (report[key] ? "" : " fail"),
          ),
        );
    parent.append(checks);
    for (const q of report.questions || []) {
      const d = el("details");
      d.append(
        el(
          "summary",
          q.questionId +
            " · " +
            ([
              "independent",
              "unambiguous",
              "grammarCorrect",
              "hintDoesNotReveal",
              "solutionReasonSound",
            ].every((k) => q[k])
              ? "通过"
              : "需检查"),
        ),
        el("p", q.reason),
      );
      parent.append(d);
    }
  }
  function renderAudit() {
    const root = $("audit");
    root.replaceChildren();
    const d = state.detail;
    if (state.kind === "units") {
      root.append(
        el("h3", "不可变内容版本"),
        el(
          "p",
          "当前第 " +
            d.currentVersion +
            " 版；预览第 " +
            d.unit.version +
            " 版。",
        ),
        el("p", "审核者：" + d.unit.authorship.reviewedBy),
        el("p", d.unit.authorship.reviewNotes),
        el("pre", "内容指纹：" + d.contentHash),
      );
      return;
    }
    root.append(
      el("h3", "当前任务"),
      el("p", d.id),
      el("p", "尝试次数：" + d.attempts + "；" + errorText(d.last_error_code)),
    );
    if (d.reviewed_by)
      root.append(
        el("h3", "人工复核"),
        el("p", d.reviewed_by),
        el("p", d.review_notes),
      );
    for (const edit of d.edits || []) {
      const section = el("section", undefined, "audit-entry");
      section.append(
        el("h3", "编辑修订"),
        el("p", edit.editor + " / " + date(edit.created_at)),
        el("p", edit.notes),
      );
      const next =
        edit.revised_job_id === d.id ? edit.source_job_id : edit.revised_job_id;
      const button = el(
        "button",
        edit.revised_job_id === d.id ? "查看原稿" : "查看后继修订",
      );
      button.addEventListener("click", () =>
        select(next).catch((e) => notice(e.message, true)),
      );
      section.append(button);
      root.append(section);
    }
    for (const run of d.runs || []) {
      const section = el("section", undefined, "audit-entry");
      section.append(
        el(
          "h3",
          "第 " +
            run.attempt +
            " 次 · " +
            (statuses[run.outcome] || run.outcome),
        ),
        el(
          "p",
          date(run.created_at) +
            "；作者 " +
            (run.author_model ||
              (d.edits?.some((e) => e.revised_job_id === d.id)
                ? "编辑修订稿"
                : "未记录作者响应")) +
            "；审题 " +
            (run.review_model || "尚无有效结果"),
        ),
      );
      const input =
          (run.author_usage?.inputTokens || 0) +
          (run.review_usage?.inputTokens || 0),
        output =
          (run.author_usage?.outputTokens || 0) +
          (run.review_usage?.outputTokens || 0);
      section.append(
        el(
          "p",
          "输入 " +
            input +
            " token / 输出 " +
            output +
            " token；规范版本 " +
            run.prompt_version,
        ),
      );
      if (run.error_code)
        section.append(el("p", errorText(run.error_code), "muted"));
      reportView(section, run.review_report);
      if (run.candidate?.rawResponse !== undefined)
        reportView(section, run.candidate);
      root.append(section);
    }
    if (!d.runs?.length)
      root.append(el("p", "任务尚未开始，请稍后刷新。", "muted"));
    if (d.candidate_hash) {
      const raw = el("details");
      raw.append(
        el("summary", "稿件身份与内容指纹"),
        el("pre", d.id + "\n" + d.candidate_hash),
      );
      root.append(raw);
    }
  }
  function updateActions() {
    for (const input of document.querySelectorAll(
      "#editor input,#editor textarea,#editor select,#editor button,#notes,#confirmed,#disconnect",
    ))
      input.disabled = state.busy;
    const d = state.detail,
      isJob = state.kind === "jobs" && d;
    const editable = isJob && d.canRevise;
    $("actions").hidden = !isJob;
    const notes = $("notes").value.trim().length >= 30,
      confirmed = $("confirmed").checked;
    $("revise").disabled = state.busy || !editable || !notes;
    $("publish").disabled =
      state.busy ||
      !isJob ||
      d.status !== "review" ||
      !d.blueprintAvailable ||
      state.dirty ||
      !notes ||
      !confirmed;
    $("reject").disabled =
      state.busy ||
      !isJob ||
      d.status !== "review" ||
      state.dirty ||
      !notes ||
      !confirmed;
    $("actionHint").textContent = state.dirty
      ? "当前有修改，须提交修订并重新审题后才能发布。"
      : isJob && d.status === "review"
        ? "发布后，尚未使用该单元的用户可以从共享题库抽取。"
        : "未通过完整审题的候选不能发布；可修改有效稿件后提交新的修订。";
    for (const id of [
      "refresh",
      "unitsTab",
      "jobsTab",
      "role",
      "level",
      "status",
      "version",
      "previous",
      "next",
    ])
      if (state.busy) $(id).disabled = true;
      else if (["previous", "next"].includes(id))
        $(id).disabled =
          id === "previous"
            ? state.offset === 0
            : state.offset + 30 >= state.total;
      else $(id).disabled = false;
  }
  async function action(kind) {
    if (state.busy) return;
    const d = state.detail,
      id = d?.id;
    if (!id) return;
    let body = {
      candidateHash: d.candidate_hash,
      notes: $("notes").value.trim(),
      confirmed: $("confirmed").checked,
    };
    if (kind === "revisions") {
      const draftBody = {
        candidateHash: d.candidate_hash,
        notes: body.notes,
        unit: structuredClone(state.draft),
      };
      const content = JSON.stringify(draftBody);
      if (!state.pendingEdit || state.pendingEdit.content !== content)
        state.pendingEdit = { content, requestId: crypto.randomUUID() };
      body = { ...draftBody, requestId: state.pendingEdit.requestId };
    }
    state.busy = true;
    updateActions();
    try {
      const result = await api("/jobs/" + id + "/" + kind, "POST", body);
      state.dirty = false;
      notice(
        kind === "revisions"
          ? "修订稿已提交，等待独立审题。"
          : kind === "publish"
            ? "单元已发布到共享题库。"
            : "候选已退回。",
      );
      state.busy = false;
      await select(result.revisedJobId || id);
    } catch (e) {
      notice(e.message, true);
    } finally {
      state.busy = false;
      updateActions();
    }
  }
  for (const [id, kind] of [
    ["revise", "revisions"],
    ["publish", "publish"],
    ["reject", "reject"],
  ])
    $(id).addEventListener("click", () => action(kind));
  for (const id of ["notes", "confirmed"])
    $(id).addEventListener("input", updateActions);
  for (const mode of ["preview", "edit", "audit"])
    $(mode + "Mode").addEventListener("click", () => {
      if (mode === "preview") renderPreview();
      showMode(mode);
    });
  async function switchKind(kind) {
    if (state.busy || !discard()) return;
    resetMedia();
    state.epoch++;
    state.selected = null;
    state.detail = null;
    state.draft = null;
    state.dirty = false;
    state.kind = kind;
    state.offset = 0;
    $("document").hidden = true;
    $("empty").hidden = false;
    $("statusFilter").hidden = kind !== "jobs";
    for (const tab of ["units", "jobs"]) {
      $(tab + "Tab").classList.toggle("selected", kind === tab);
      $(tab + "Tab").setAttribute("aria-selected", String(kind === tab));
    }
    await load();
  }
  $("unitsTab").addEventListener("click", () =>
    switchKind("units").catch((e) => notice(e.message, true)),
  );
  $("jobsTab").addEventListener("click", () =>
    switchKind("jobs").catch((e) => notice(e.message, true)),
  );
  for (const id of ["role", "level", "status"])
    $(id).addEventListener("change", () => {
      state.offset = 0;
      load().catch((e) => notice(e.message, true));
    });
  $("previous").addEventListener("click", () => {
    state.offset = Math.max(0, state.offset - 30);
    load().catch((e) => notice(e.message, true));
  });
  $("next").addEventListener("click", () => {
    state.offset += 30;
    load().catch((e) => notice(e.message, true));
  });
  $("version").addEventListener("change", () =>
    select(state.selected, Number($("version").value)).catch((e) =>
      notice(e.message, true),
    ),
  );
  $("refresh").addEventListener("click", () => {
    if (state.selected)
      select(state.selected).catch((e) => notice(e.message, true));
    else load().catch((e) => notice(e.message, true));
  });
  $("disconnect").addEventListener("click", () => {
    if (!discard()) return;
    resetMedia();
    state.dirty = false;
    sessionStorage.removeItem("lingotrip-admin-token");
    location.reload();
  });
  $("editor").addEventListener("submit", (e) => e.preventDefault());
  $("loginForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    state.token = $("token").value.trim();
    try {
      await load();
      sessionStorage.setItem("lingotrip-admin-token", state.token);
      $("token").value = "";
      $("loginError").textContent = "";
      $("login").close();
    } catch (error) {
      $("loginError").textContent = error.message;
    }
  });
  $("login").addEventListener("cancel", (e) => e.preventDefault());
  window.addEventListener("pagehide", resetMedia);
  window.addEventListener("beforeunload", (e) => {
    if (state.dirty) {
      e.preventDefault();
      e.returnValue = "";
    }
  });
  if (state.token) load().catch((e) => notice(e.message, true));
  else $("login").showModal();
})();
`;
