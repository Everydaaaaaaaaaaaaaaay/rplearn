import type { FastifyInstance } from "fastify";
import { learningAdminCss, learningAdminJavascript } from "./admin-console-assets.js";
const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LingoTrip · 挑战内容管理</title><link rel="stylesheet" href="/internal/admin/learning/console.css"></head><body>
<header class="top"><a class="brand" href="/internal/admin/ai">LingoTrip <span>内容工作台</span></a><nav><a href="/internal/admin/learning/bank">公共题库</a><a href="/internal/admin/ai">模型控制台</a><button id="refresh" type="button">刷新</button><button id="disconnect" type="button">退出</button></nav></header>
<main><section class="heading"><div><h1>挑战内容</h1><p>让每一段剧情，带来清楚、准确的练习。</p></div><span class="connection" id="connection">尚未连接</span></section>
<div id="notice" role="status" aria-live="polite"></div>
<div class="workspace"><aside class="library"><div class="switcher" role="tablist" aria-label="内容来源"><button id="unitsTab" class="selected" role="tab" aria-selected="true">正式单元</button><button id="jobsTab" role="tab" aria-selected="false">生成与待审</button></div><div class="filters"><label>角色<select id="role"><option value="">全部角色</option><option value="oliver">Oliver</option><option value="ruby">Ruby</option><option value="marcus">Marcus</option></select></label><label>水平<select id="level"><option value="">全部水平</option></select></label><label id="statusFilter" hidden>状态<select id="status"><option value="">全部状态</option><option value="review">等待审核</option><option value="failed">未通过</option><option value="pending">等待生成</option><option value="running">正在生成</option><option value="published">已发布</option></select></label></div><p id="listCount" class="muted">连接后读取内容</p><div id="items" aria-label="单元列表"></div><div class="pager"><button id="previous">上一页</button><span id="pageNumber">1</span><button id="next">下一页</button></div></aside>
<section class="detail" aria-label="内容详情"><div id="empty" class="empty"><div class="book-mark" aria-hidden="true">✦</div><h2>从一个单元开始</h2><p>选择左侧内容，查看剧情、题目与审核记录。</p></div><article id="document" hidden><div class="document-head"><div><span id="detailBadge" class="badge"></span><h2 id="detailTitle"></h2><p id="detailMeta" class="muted"></p></div><label id="versionLabel" hidden>版本<select id="version"></select></label></div><p id="stateHint" class="state-hint"></p><div class="mode-switch"><button id="previewMode" class="selected">预览</button><button id="editMode">编辑修订稿</button><button id="auditMode">审核与记录</button></div><div id="preview"></div><form id="editor" hidden autocomplete="off"><p class="editor-note">修改后需要重新审题。单元身份、题型与来源保持绑定。</p><div id="editFields"></div></form><section id="audit" hidden></section><section id="actions" class="actions" hidden><h3>审核操作</h3><label>修改或审核说明<textarea id="notes" rows="3" minlength="30" maxlength="1000" placeholder="至少 30 字符，说明逐题检查结果或具体修改原因。"></textarea></label><label class="confirmation"><input id="confirmed" type="checkbox">我已逐题核对题干、答案、提示、解析与水平匹配。</label><p id="actionHint" class="muted"></p><div class="action-buttons"><button id="revise" type="button">提交修订并重新审题</button><button id="publish" type="button" class="primary">发布到共享题库</button><button id="reject" type="button" class="danger">退回候选</button></div></section></article></section></div></main>
<dialog id="login"><form id="loginForm"><h2>连接内容工作台</h2><p>使用现有管理员凭据。仅在当前浏览器会话中保存。</p><label>管理员凭据<input id="token" type="password" autocomplete="off" required></label><p id="loginError" role="alert"></p><button type="submit" class="primary">连接</button></form></dialog>
<script src="/internal/admin/learning/console.js" defer></script></body></html>`;
export function registerLearningAdminConsole(app: FastifyInstance) {
  const headers = {
    "cache-control": "no-store",
    "content-security-policy":
      "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' blob:; media-src 'self' blob:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
  };
  for (const [path, type, body] of [
    ["/internal/admin/learning", "text/html; charset=utf-8", html],
    [
      "/internal/admin/learning/console.css",
      "text/css; charset=utf-8",
      learningAdminCss,
    ],
    [
      "/internal/admin/learning/console.js",
      "application/javascript; charset=utf-8",
      learningAdminJavascript,
    ],
  ] as const)
    app.get(path, { schema: { hide: true } }, (_request, reply) =>
      reply.headers(headers).type(type).send(body),
    );
}
