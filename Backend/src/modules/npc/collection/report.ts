import { hashDistance } from "./images.js";
import type { CollectionState, DiscoveryPlan, Review } from "./types.js";

export function collectionReport(plan: DiscoveryPlan, state: CollectionState) {
  const candidates = Object.values(state.candidates);
  const files = candidates.filter((candidate) => candidate.file);
  const similar: { left: string; right: string; distance: number; exact: boolean }[] =
    [];
  for (let i = 0; i < files.length; i += 1) {
    for (let j = i + 1; j < files.length; j += 1) {
      const left = files[i];
      const right = files[j];
      if (!left?.file || !right?.file) continue;
      const distance = hashDistance(left.file.dhash, right.file.dhash);
      if (distance <= 4)
        similar.push({
          left: left.id,
          right: right.id,
          distance,
          exact: left.file.sha256 === right.file.sha256,
        });
    }
  }
  return {
    version: 1,
    discovered: candidates.length,
    eligibleForReview: candidates.filter(
      (candidate) => candidate.source.rightsScreen === "eligible-for-review",
    ).length,
    manualLicenseReview: candidates.filter(
      (candidate) => candidate.source.rightsScreen === "manual-license-review",
    ).length,
    downloaded: files.length,
    distinctFiles: new Set(files.map((candidate) => candidate.file?.sha256)).size,
    approved: 0, // Acquisition never implies approval.
    searchErrors: Object.values(state.searches).filter((search) => search.error).length,
    downloadErrors: candidates.filter((candidate) => candidate.downloadError).length,
    sources: ["commons", "cleveland", "artic", "openverse", "met"].map((provider) => ({
      provider,
      downloaded: files.filter((candidate) => candidate.source.provider === provider)
        .length,
    })),
    topics: plan.topics.map((topic) => {
      const matches = candidates.filter((candidate) =>
        candidate.topicIds.includes(topic.id),
      );
      const count = new Set(
        matches.flatMap((candidate) => (candidate.file ? [candidate.file.sha256] : [])),
      ).size;
      return {
        id: topic.id,
        label: topic.label,
        domain: topic.domain,
        target: topic.target,
        discovered: matches.length,
        downloaded: count,
        deficit: Math.max(0, topic.target - count),
        // These are retrieval leads, not a claim that the images depict the topic correctly.
        verifiedCultureCoverage: 0,
      };
    }),
    difficultCrops: files
      .filter((candidate) => (candidate.file?.cropRetention ?? 1) < 0.55)
      .map((candidate) => candidate.id),
    similar,
  };
}
const escape = (value: string) =>
  value.replace(
    /[&<>"']/gu,
    (character) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        character
      ] ?? character,
  );
export function reviewHTML(
  plan: DiscoveryPlan,
  state: CollectionState,
  review?: Review,
): string {
  const decisions = new Map(
    review?.decisions.map((decision) => [decision.candidateId, decision]),
  );
  const labels = new Map(plan.topics.map((topic) => [topic.id, topic.label]));
  const cards = Object.values(state.candidates)
    .filter((candidate) => candidate.file)
    .map((candidate) => {
      const file = candidate.file;
      if (!file) return "";
      const decision = decisions.get(candidate.id);
      const status =
        decision?.decision === "approve"
          ? "已审核通过"
          : decision?.decision === "reject"
            ? `本批不采用：${decision.reason}`
            : "待审核";
      const reviewedTags =
        decision?.decision === "approve"
          ? `<p>审核标签：${escape([...decision.metadata.cultures, ...decision.metadata.subjects].join(" · "))}</p>`
          : "";
      const url = candidate.source.recordURL;
      const safeURL = url.startsWith("https://") ? url : "#";
      return `<article data-topics="${escape(candidate.topicIds.join(" "))}"><div class="image"><img loading="lazy" src="${escape(file.path)}" alt="${escape(candidate.source.title)}"></div><h2>${escape(candidate.source.title)}</h2>${reviewedTags}<p><strong>${escape(status)}</strong> <img class="small" src="${escape(file.path)}" alt="40 像素预览"></p><a href="${escape(file.path)}" target="_blank" rel="noopener noreferrer">查看下载原图</a><p>检索线索：${escape(candidate.topicIds.map((id) => labels.get(id) ?? id).join(" · "))}</p><p>${escape(candidate.source.creator)}</p><p>${escape(candidate.source.licenseLabel)} · ${escape(candidate.source.provider)} · 方形保留 ${String(Math.round(file.cropRetention * 100))}%</p><a href="${escape(safeURL)}" target="_blank" rel="noopener noreferrer">原始来源与授权</a><details><summary>标识与审核记录</summary><code>${escape(candidate.id)}</code><p>SHA-256: ${escape(file.sha256)}</p><pre>${escape(JSON.stringify(candidate.source.evidence, null, 2))}</pre></details></article>`;
    })
    .join("\n");
  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'"><title>NPC 文化头像 · 候选审核</title><style>body{margin:32px;background:#f5f3ef;color:#242421;font:15px/1.6 system-ui}h1{font-size:28px}header{max-width:880px;margin-bottom:28px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(235px,1fr));gap:18px}article{min-width:0;background:white;border:1px solid #ddd9d0;border-radius:16px;padding:16px}.image{height:200px;display:grid;place-items:center;background:#eeece6;border-radius:12px}img{width:180px;height:180px;object-fit:cover;border-radius:50%}.small{width:40px;height:40px;vertical-align:middle}h2{font-size:16px;line-height:1.4}p{color:#5b5b54}a{color:#28614d}code,pre{font-size:11px;white-space:pre-wrap;overflow-wrap:anywhere}summary{cursor:pointer}</style><header><h1>NPC 文化头像 · 候选审核</h1><p>尚未批准入库的图片不可用于分配；具体审核状态见各卡片。主题来自搜索线索，需要核对实际内容。圆形展示只用于预览，原始下载文件没有裁切。</p><p>请检查文化含义、人物与品牌权利、圆形裁切、小尺寸辨识度、重复图及署名要求；在 review.json 中记录决定。</p></header><main class="grid">${cards}</main></html>`;
}
