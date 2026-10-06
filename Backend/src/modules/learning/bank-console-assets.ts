export const bankCss = String.raw`
.bank-heading {
  display: flex;
  align-items: center;
  gap: 20px;
  margin: 18px 0;
}
.bank-heading h1,
.bank-heading h2 {
  margin: 0;
  flex: 1;
}
.bank-filters {
  display: flex;
  gap: 16px;
  border-block: 1px solid var(--line);
  padding: 14px 0;
  flex-wrap: wrap;
}
.bank-filters label {
  flex: 1;
  min-width: 130px;
}
.bank-workspace {
  display: grid;
  grid-template-columns: minmax(260px, 34%) 1fr;
  gap: 32px;
  margin-top: 20px;
}
.bank-workspace {
  height: calc(100dvh - 320px);
  min-height: 420px;
}
.bank-workspace aside,
#detail {
  overflow: auto;
  overscroll-behavior: contain;
}
.bank-workspace aside {
  border-right: 1px solid var(--line);
  padding-right: 24px;
}
.bank-row {
  display: block;
  width: 100%;
  text-align: left;
  background: none;
  border: 0;
  border-bottom: 1px solid var(--line);
  border-radius: 0;
  padding: 16px 6px;
}
.bank-row[aria-current="true"] {
  border-left: 3px solid var(--blue);
  background: #edf3fc;
}
.bank-row span {
  display: block;
  color: var(--muted);
  font-size: 12px;
  margin-bottom: 5px;
}
.bank-row strong {
  font-weight: 500;
  line-height: 1.6;
}
.bank-question {
  border-bottom: 1px solid var(--line);
  padding: 16px 0;
}
.bank-question h3 {
  font-size: 16px;
}
.bank-question p {
  white-space: pre-wrap;
  line-height: 1.7;
  max-width: 75ch;
}
.bank-editor {
  display: grid;
  gap: 14px;
}
.bank-editor textarea {
  width: 100%;
  min-height: 75px;
}
.bank-editor input {
  width: 100%;
}
.bank-editor label {
  display: block;
}
.bank-editor .confirmation {
  display: flex;
  gap: 10px;
}
.bank-editor .confirmation input {
  width: auto;
}
.bank-editor fieldset {
  border: 0;
  border-top: 1px solid var(--line);
  padding: 14px 0;
}
.bank-editor legend {
  font-weight: 600;
}
#coverage {
  border-top: 2px solid var(--blue);
  margin-top: 30px;
  padding-top: 10px;
}
#coverage table {
  border-collapse: collapse;
  width: 100%;
  font-size: 13px;
  margin-top: 24px;
}
#coverage td,
#coverage th {
  text-align: left;
  border-bottom: 1px solid var(--line);
  padding: 12px 8px;
}
#coverage > label {
  display: inline-block;
  margin-right: 16px;
}
details {
  margin: 20px 0;
}
summary {
  cursor: pointer;
}
pre {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
#notice:empty {
  display: none;
}
@media (max-width: 760px) {
  .bank-workspace {
    grid-template-columns: 1fr;
    height: auto;
  }
  .bank-workspace aside,
  #detail {
    overflow: visible;
  }
  .bank-workspace {
    height: calc(100dvh - 320px);
    min-height: 420px;
  }
  .bank-workspace aside,
  #detail {
    overflow: auto;
    overscroll-behavior: contain;
  }
  .bank-workspace aside {
    border-right: 0;
    padding-right: 0;
  }
  .top {
    height: auto;
    min-height: 68px;
    flex-wrap: wrap;
    padding: 14px;
  }
  #coverage {
    overflow: auto;
  }
}
`;
export const bankJavascript = String.raw`
(() => {
  const $ = (id) => document.getElementById(id),
    node = (tag, text) => {
      const n = document.createElement(tag);
      if (text !== undefined) n.textContent = text;
      return n;
    };
  const topics = {
    daily: "日常",
    books: "阅读",
    community: "社区",
    outdoors: "外出",
    projects: "项目",
  };
  const types = {
    choice: "选择",
    listeningChoice: "听辨",
    arrange: "组句",
    completion: "填空",
    dictation: "听写",
    matching: "配对",
  };
  const levels = {
    kindergarten: "启蒙",
    ...Object.fromEntries(
      Array.from({ length: 6 }, (_, i) => [
        "primary" + (i + 1),
        "小学" + (i + 1) + "年级",
      ]),
    ),
    ...Object.fromEntries(
      Array.from({ length: 3 }, (_, i) => [
        "junior" + (i + 1),
        "初中" + (i + 1) + "年级",
      ]),
    ),
    ...Object.fromEntries(
      Array.from({ length: 3 }, (_, i) => [
        "senior" + (i + 1),
        "高中" + (i + 1) + "年级",
      ]),
    ),
  };
  for (const [id, values] of Object.entries({
    topic: topics,
    type: types,
    level: levels,
  }))
    for (const [value, label] of Object.entries(values)) {
      const o = node("option", label);
      o.value = value;
      $(id).append(o);
    }
  let mediaUrls = [];
  let token = sessionStorage.getItem("lingotrip-admin-token") || "",
    offset = 0,
    total = 0,
    selected = null,
    epoch = 0,
    dirty = false,
    busy = false;
  function notice(text) {
    $("notice").textContent = text;
  }
  async function api(path, body) {
    const r = await fetch("/internal/admin/learning/bank" + path, {
      method: body ? "POST" : "GET",
      headers: {
        authorization: "Bearer " + token,
        ...(body ? { "content-type": "application/json" } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    const d = await r.json();
    if (!r.ok) {
      if (r.status === 401 || r.status === 403) {
        token = "";
        sessionStorage.removeItem("lingotrip-admin-token");
        if (!$("login").open) $("login").showModal();
      }
      throw Error(d.error?.message || d.message || "请求未完成");
    }
    return d;
  }
  function guard() {
    return !dirty || confirm("离开会放弃未保存的修改，是否继续？");
  }
  function action(button, fn) {
    button.addEventListener("click", () => {
      if (busy) return;
      Promise.resolve()
        .then(fn)
        .catch((e) => notice(e.message));
    });
  }
  async function list() {
    const current = ++epoch;
    const query = new URLSearchParams({ offset: String(offset), limit: "30" });
    for (const id of ["level", "topic", "type", "goal", "published"])
      if ($(id).value) query.set(id, $(id).value);
    const d = await api("/questions?" + query);
    if (current !== epoch) return;
    total = d.total;
    $("count").textContent = total + " 道";
    $("page").textContent = String(offset / 30 + 1);
    $("previous").disabled = offset === 0;
    $("next").disabled = offset + 30 >= total;
    $("list").replaceChildren();
    for (const row of d.items) {
      const q = row.payload,
        b = node("button");
      b.className = "bank-row";
      b.dataset.questionId = q.id;
      b.setAttribute("aria-current", String(selected === q.id));
      b.append(
        node(
          "span",
          (levels[q.level] || q.level) +
            " · " +
            types[q.question.type] +
            " · " +
            (row.published ? "已发布" : "已下架"),
        ),
        node("strong", q.question.prompt),
      );
      action(b, () => open(q.id));
      $("list").append(b);
    }
    if (!d.items.length) $("list").append(node("p", "没有符合条件的题目。"));
  }
  function renderQuestion(q, parent) {
    const article = node("article");
    article.className = "bank-question";
    article.append(
      node("h3", types[q.type] + " · " + q.instruction),
      node("p", q.prompt),
    );
    for (const o of q.options || q.tokens || []) {
      article.append(
        node(
          "p",
          o.id + " · " + o.text + (o.imageAssetId ? " · 图片选项" : ""),
        ),
      );
    }
    if (q.left) {
      article.append(node("p", "左侧：" + q.left.map((item) => item.text).join("、")));
      article.append(node("p", "右侧：" + q.right.map((item) => item.text).join("、")));
    }
    const optionText = (items, id) => items.find((item) => item.id === id)?.text || id;
    let solution;
    if (q.answer) solution = optionText(q.options, q.answer);
    if (q.acceptedAnswers) solution = q.acceptedAnswers.join(" / ");
    if (q.acceptedOrders) solution = q.acceptedOrders.map((order) => order.map((id) => optionText(q.tokens, id)).join(" ")).join(" / ");
    if (q.answerPairs) solution = q.answerPairs.map((pair) => optionText(q.left, pair.left) + " → " + optionText(q.right, pair.right)).join("；");
    if (solution) article.append(node("p", "答案：" + solution));
    if (q.audio) article.append(node("p", "听力材料：" + q.audio.text));
    article.append(node("p", "解析：" + q.explanation));
    parent.append(article);
  }
  function field(parent, label, value, onChange, multiline = true) {
    const wrap = node("label", label),
      input = node(multiline ? "textarea" : "input");
    input.value = value;
    input.addEventListener("input", () => {
      onChange(input.value);
      dirty = true;
    });
    wrap.append(input);
    parent.append(wrap);
    return input;
  }
  async function open(id) {
    if (!guard()) return;
    dirty = false;
    const current = ++epoch;
    const d = await api("/questions/" + encodeURIComponent(id));
    if (current !== epoch) return;
    selected = id;
    $("list").querySelectorAll("button").forEach((button) => button.setAttribute("aria-current", String(button.dataset.questionId === id)));
    const draft = structuredClone(d.payload);
    draft.version++;
    const root = $("detail");
    root.replaceChildren();
    root.append(
      node(
        "h2",
        (levels[draft.level] || draft.level) +
          " · " +
          types[draft.question.type],
      ),
      node("p", draft.question.goalId + " · 版本 " + d.payload.version),
    );
    renderQuestion(draft.question, root);
    for (const url of mediaUrls) URL.revokeObjectURL(url);
    mediaUrls = [];
    for (const kind of ["audio", "images"])
      for (const asset of d.media?.[kind] || []) {
        const host = node("div"),
          button = node("button", kind === "audio" ? "试听录音" : "查看图片");
        host.append(button);
        root.append(host);
        action(button, async () => {
          button.disabled = true;
          try {
            const response = await fetch(
              "/internal/admin/learning/bank/questions/" +
                id +
                "/media/" +
                kind +
                "/" +
                asset.id +
                "?hash=" +
                d.content_hash,
              { headers: { authorization: "Bearer " + token } },
            );
            if (!response.ok) throw Error("素材加载失败，请重试。");
            const blob = await response.blob();
            if (selected !== id) return;
            const url = URL.createObjectURL(blob);
            mediaUrls.push(url);
            const media = node(kind === "audio" ? "audio" : "img");
            media.src = url;
            if (kind === "audio") media.controls = true;
            else {
              media.alt = "题目选项图片";
              media.style.maxWidth = "220px";
            }
            host.replaceChildren(media);
          } catch (error) {
            button.disabled = false;
            throw error;
          }
        });
      }
    const form = node("form");
    form.className = "bank-editor";
    form.addEventListener("submit", (e) => e.preventDefault());
    const topicLabel = node("label", "场景分类"),
      topic = node("select");
    for (const [key, label] of Object.entries(topics)) {
      const o = node("option", label);
      o.value = key;
      topic.append(o);
    }
    topic.value = draft.topic;
    topic.onchange = () => {
      draft.topic = topic.value;
      dirty = true;
    };
    topicLabel.append(topic);
    form.append(topicLabel);
    field(
      form,
      "限定角色（留空则共享；多个用逗号分隔）",
      draft.roleKeys.join(","),
      (v) =>
        (draft.roleKeys = v
          .split(",")
          .map((x) => x.trim())
          .filter(Boolean)),
      false,
    );
    for (const [key, label] of Object.entries({
      instruction: "操作要求",
      prompt: "题干",
      hint: "提示",
      explanation: "解析",
      difficultyReason: "难度依据",
    }))
      field(form, label, draft.question[key], (v) => (draft.question[key] = v));
    const q = draft.question;
    for (const [key, label] of [
      ["options", "选项"],
      ["tokens", "词块"],
      ["left", "左列"],
      ["right", "右列"],
    ])
      if (q[key]) {
        const group = node("fieldset");
        group.append(node("legend", label));
        for (const item of q[key])
          field(group, item.id, item.text, (v) => (item.text = v), false);
        form.append(group);
      }
    if (q.answer) {
      const label = node("label", "正确选项"),
        select = node("select");
      for (const option of q.options) {
        const o = node("option", option.id);
        o.value = option.id;
        select.append(o);
      }
      select.value = q.answer;
      select.onchange = () => {
        q.answer = select.value;
        dirty = true;
      };
      label.append(select);
      form.append(label);
    }
    if (q.acceptedAnswers)
      field(
        form,
        "可接受答案（每行一个）",
        q.acceptedAnswers.join("\n"),
        (v) =>
          (q.acceptedAnswers = v
            .split("\n")
            .map((x) => x.trim())
            .filter(Boolean)),
      );
    if (q.acceptedOrders)
      field(
        form,
        "可接受词块顺序（每行一种，以空格分隔标识）",
        q.acceptedOrders.map((x) => x.join(" ")).join("\n"),
        (v) =>
          (q.acceptedOrders = v
            .split("\n")
            .filter((x) => x.trim())
            .map((x) => x.trim().split(/\s+/))),
      );
    if (q.answerPairs)
      field(
        form,
        "正确配对（每行左标识=右标识）",
        q.answerPairs.map((x) => x.left + "=" + x.right).join("\n"),
        (v) =>
          (q.answerPairs = v
            .split("\n")
            .filter((x) => x.trim())
            .map((x) => {
              const [left, right] = x.trim().split("=");
              return { left, right };
            })),
      );
    field(
      form,
      "逐题审核说明（至少 30 字符）",
      "",
      (v) => (draft.reviewNotes = v),
    );
    draft.reviewNotes = "";
    const confirmLabel = node("label"),
      confirmed = node("input");
    confirmed.type = "checkbox";
    confirmLabel.className = "confirmation";
    confirmLabel.append(
      confirmed,
      document.createTextNode("已独立核对题干、答案、解析、年级与场景适配"),
    );
    form.append(confirmLabel);
    const buttons = node("div");
    buttons.className = "action-buttons";
    for (const [published, label] of [
      [true, "发布修订"],
      [false, "下架"],
      ["new", "另存为新题"],
    ]) {
      const b = node("button", label);
      b.type = "button";
      b.className = published ? "primary" : "danger";
      action(b, async () => {
        if (!confirmed.checked || draft.reviewNotes.trim().length < 30)
          throw Error("请完成逐题核对并填写至少 30 字符审核说明。");
        busy = true;
        buttons.querySelectorAll("button").forEach((x) => (x.disabled = true));
        try {
          const saved = await api(
            "/questions/" + id + (published === "new" ? "/variants" : ""),
            {
              expectedHash: d.content_hash,
              question: draft,
              ...(published === "new" ? {} : { published }),
              confirmed: true,
            },
          );
          dirty = false;
          notice(
            published
              ? "修订已发布；已开始的挑战保留原题。"
              : "已下架；已开始的挑战和补答仍可继续。",
          );
          await open(saved.id);
          await list();
        } finally {
          busy = false;
          buttons
            .querySelectorAll("button")
            .forEach((x) => (x.disabled = false));
        }
      });
      buttons.append(b);
    }
    form.append(buttons);
    root.append(form);
    const audit = node("details");
    audit.append(node("summary", "来源与审核记录"));
    for (const r of draft.references)
      audit.append(node("p", r.sourceId + " · " + r.unit + " · " + r.pages));
    for (const a of d.audit)
      audit.append(
        node("p", "v" + a.version + " · " + a.operator + " · " + a.notes),
      );
    root.append(audit);
  }
  for (const id of ["level", "topic", "type", "goal", "published"])
    $(id).addEventListener("change", () => {
      offset = 0;
      list().catch((e) => notice(e.message));
    });
  action($("refresh"), list);
  action($("previous"), () => {
    offset = Math.max(0, offset - 30);
    return list();
  });
  action($("next"), () => {
    offset += 30;
    return list();
  });
  action($("coverageButton"), async () => {
    const d = await api("/coverage");
    $("coverage").hidden = false;
    $("coverageRows").replaceChildren();
    $("blueprint").replaceChildren();
    for (const r of d.goals) {
      const tr = node("tr");
      for (const v of [
        levels[r.level] || r.level,
        r.goal,
        types[r.type],
        r.questions,
      ])
        tr.append(node("td", v));
      $("coverageRows").append(tr);
    }
    for (const b of d.blueprints) {
      const o = node(
        "option",
        (levels[b.payload.level] || b.payload.level) + " · " + b.payload.title,
      );
      o.value = b.id;
      $("blueprint").append(o);
    }
    $("coverage").scrollIntoView({ behavior: "auto" });
  });
  action($("closeCoverage"), () => {
    $("coverage").hidden = true;
  });
  action($("previewButton"), async () => {
    const d = await api(
      "/preview/" +
        encodeURIComponent($("blueprint").value) +
        "?roleKey=" +
        encodeURIComponent($("previewRole").value),
    );
    $("preview").replaceChildren();
    if (d.missing) {
      $("preview").append(node("p", "题库不足，无法满足本规则的六题配额。"));
      return;
    }
    for (const beat of d.unit.beats)
      $("preview").append(node("p", beat.speaker + "：" + beat.text));
    for (const q of d.unit.questions) renderQuestion(q, $("preview"));
  });
  action($("logout"), () => {
    if (!guard()) return;
    token = "";
    sessionStorage.removeItem("lingotrip-admin-token");
    location.reload();
  });
  $("loginForm").addEventListener("submit", async (e) => {
    e.preventDefault();
    token = $("token").value.trim();
    try {
      await list();
      sessionStorage.setItem("lingotrip-admin-token", token);
      $("token").value = "";
      $("login").close();
    } catch (e) {
      $("loginError").textContent = e.message;
    }
  });
  window.addEventListener("beforeunload", (e) => {
    if (dirty) {
      e.preventDefault();
      e.returnValue = "";
    }
  });
  if (token) list().catch((e) => notice(e.message));
  else $("login").showModal();
})();
`;
