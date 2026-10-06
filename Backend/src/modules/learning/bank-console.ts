import { bankCss, bankJavascript } from "./bank-console-assets.js";
import type { FastifyInstance } from "fastify";

const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LingoTrip · 公共题库</title><link rel="stylesheet" href="/internal/admin/learning/console.css"><link rel="stylesheet" href="/internal/admin/learning/bank.css"></head><body>
<header class="top"><a class="brand" href="/internal/admin/learning">LingoTrip <span>公共题库</span></a><nav><a href="/internal/admin/learning">专属单元</a><button id="coverageButton">覆盖与组卷</button><button id="logout">退出</button></nav></header>
<main><div class="bank-heading"><h1>公共题库</h1><span id="count"></span><button id="refresh" aria-label="刷新题库">↻</button></div><p id="notice" role="status" aria-live="polite"></p>
<div class="bank-filters"><label>年级<select id="level"><option value="">全部年级</option></select></label><label>场景<select id="topic"><option value="">全部场景</option></select></label><label>题型<select id="type"><option value="">全部题型</option></select></label><label>目标<input id="goal" placeholder="按学习目标筛选"></label><label>状态<select id="published"><option value="">全部状态</option><option value="true">已发布</option><option value="false">已下架</option></select></label></div>
<div class="bank-workspace"><aside><div id="list"></div><div class="pager"><button id="previous" aria-label="上一页">←</button><span id="page">1</span><button id="next" aria-label="下一页">→</button></div></aside><section id="detail" aria-label="题目详情"><p class="muted">选择一道题查看材料、答案与审核记录。</p></section></div>
<section id="coverage" hidden><div class="bank-heading"><h2>覆盖与组卷</h2><button id="closeCoverage" aria-label="关闭覆盖统计">×</button></div><label>组卷规则<select id="blueprint"></select></label><label>角色范围<input id="previewRole" value="character.preview"></label><button id="previewButton">预览六题</button><div id="preview"></div><table><thead><tr><th>年级</th><th>学习目标</th><th>题型</th><th>已发布</th></tr></thead><tbody id="coverageRows"></tbody></table></section>
</main><dialog id="login"><form id="loginForm"><h2>连接公共题库</h2><label>管理员凭据<input id="token" type="password" autocomplete="off" required></label><p id="loginError" role="alert"></p><button class="primary">连接</button></form></dialog><script src="/internal/admin/learning/bank.js" defer></script></body></html>`;

export function registerLearningBankConsole(app: FastifyInstance) {
  const headers = {
    "cache-control": "no-store",
    "content-security-policy":
      "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' blob:; media-src 'self' blob:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
  };
  for (const [path, type, body] of [
    ["bank", "text/html; charset=utf-8", html],
    ["bank.css", "text/css; charset=utf-8", bankCss],
    ["bank.js", "application/javascript; charset=utf-8", bankJavascript],
  ] as const) {
    app.get(
      `/internal/admin/learning/${path}`,
      { schema: { hide: true } },
      (_request, reply) => reply.headers(headers).type(type).send(body),
    );
  }
}
