export const diagnosticsHtml = `
<section id="diagnostics" class="panel">
  <div class="section-head"><div><h2>报错与日志</h2><p>查看 API 与后台任务日志，按请求编号关联排查。此处使用独立筛选，不受顶部用户和成本周期影响。</p></div><button id="logsRefresh" class="button">刷新日志</button></div>
  <form id="logsFilters" class="inline">
    <label>时间 <select id="logsHours"><option value="1">近 1 小时</option><option value="6">近 6 小时</option><option value="24" selected>近 24 小时</option><option value="72">近 3 天</option></select></label>
    <label>服务 <select id="logsService"><option value="all">全部服务</option><option value="api">API</option><option value="worker">后台任务</option></select></label>
    <label>级别 <select id="logsLevel"><option value="all">全部级别</option><option value="error">错误</option><option value="warn">警告</option><option value="info">信息</option></select></label>
    <input id="logsRequest" placeholder="请求 / AI / 操作编号（精确匹配）" aria-label="请求编号" maxlength="200">
    <input id="logsCode" placeholder="错误码（精确匹配）" aria-label="错误码" maxlength="100">
    <button class="button" type="submit">查询</button><button id="logsReset" type="button" class="button ghost">清空筛选</button>
  </form>
  <p id="logsNotice" role="status"></p><p id="logsError" class="error" role="alert"></p>
  <div id="logsSummary" class="metric-grid"></div>
  <article class="card"><h3>错误聚合</h3><p>统计当前筛选内的失败；同一请求的多条报错合并计数。点击错误码筛选日志。</p><div id="logsGroups" class="inline"></div></article>
  <div class="table-wrap card"><table><thead><tr><th>时间 / 服务</th><th>级别 / 事件</th><th>路由 / 任务</th><th>状态 / 错误</th><th>耗时</th><th>请求编号</th><th>详情</th></tr></thead><tbody id="logsRows"></tbody></table></div>
  <div class="inline"><button id="logsPrevious" class="button ghost">上一页</button><span id="logsPage"></span><button id="logsNext" class="button ghost">下一页</button></div>
</section>
<dialog id="logsDetail"><form method="dialog" class="dialog-card"><h2>日志详情</h2><p>仅展示诊断字段，不包含对话正文、密钥和原始请求。</p><pre id="logsDetailText"></pre><div class="dialog-actions"><button id="logsTrace" type="button" class="button">查看关联日志</button><button class="button ghost">关闭</button></div></form></dialog>`;

export const diagnosticsCss = `#logsSummary{grid-template-columns:repeat(4,minmax(0,1fr))}#logsFilters{gap:12px}#logsNotice{color:var(--muted);font-size:12px}#logsDetailText{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px;line-height:1.7}#diagnostics>.card,#diagnostics>.table-wrap{margin-bottom:18px}#logsGroups{max-height:200px;overflow:auto}@media(max-width:700px){#logsSummary{grid-template-columns:repeat(2,minmax(0,1fr))}#logsFilters input{width:100%}}`;

export const diagnosticsJavascript = `
  let logsOffset=0, logsTotal=0, logsGeneration=0, logsSelected=null;
  async function loadDiagnostics(){
    const generation=++logsGeneration;
    const params=new URLSearchParams({hours:$('logsHours').value,service:$('logsService').value,level:$('logsLevel').value,requestId:$('logsRequest').value.trim(),errorCode:$('logsCode').value.trim(),offset:String(logsOffset),limit:'50'});
    $('logsError').textContent='';$('logsNotice').textContent='正在读取日志…';
    $('logsPrevious').disabled=true;$('logsNext').disabled=true;
    try{
      const result=await api('/internal/admin/ai/diagnostics?'+params);
      if(generation!==logsGeneration)return;
      logsTotal=result.total;
      $('logsNotice').textContent=(result.truncated?'⚠ 日志超过上限，仅统计最近 20,000 条；请缩小时间范围。 ':'')+'读取 '+fmt(result.scanned)+' 条，当前筛选 '+fmt(result.total)+' 条。更新于 '+new Date(result.generatedAt).toLocaleString()+(result.oldest?'；最早可见 '+new Date(result.oldest).toLocaleString():'')+'。日志按服务器保留期限可用，缓存 10 秒。';
      const metrics=[['失败请求 / 事件',result.summary.failures],['服务端错误',result.summary.serverErrors],['AI 流内失败',result.summary.streamErrors],['AI 客户端中断',result.summary.disconnected]];
      $('logsSummary').replaceChildren();metrics.forEach(([label,value])=>{const card=document.createElement('article');card.className='metric';const name=document.createElement('span');name.textContent=label;const count=document.createElement('b');count.textContent=fmt(value);card.append(name,count);$('logsSummary').append(card)});
      $('logsGroups').replaceChildren();result.errors.forEach(group=>{const button=document.createElement('button');button.className='button ghost';button.textContent=group.code+' · '+group.count;button.addEventListener('click',()=>{$('logsCode').value=group.code;logsOffset=0;loadDiagnostics()});$('logsGroups').append(button)});if(!result.errors.length)$('logsGroups').textContent='当前筛选暂无报错';
      $('logsRows').replaceChildren();result.records.forEach(row=>{const tr=document.createElement('tr');cell(tr,new Date(row.time).toLocaleString(),row.service);const level=cell(tr,({info:'信息',warn:'警告',error:'错误'})[row.level],row.event);if(row.level==='error')level.className='error';cell(tr,row.route||row.task||'—',row.model);cell(tr,row.errorCode||row.outcome||String(row.statusCode||'—'));cell(tr,row.durationMs===undefined?'—':fmt(row.durationMs)+' ms',row.firstDeltaMs===undefined?'':'首字 '+row.firstDeltaMs+' ms');cell(tr,short(row.requestId||row.aiRequestId||row.jobId));const td=document.createElement('td');const button=document.createElement('button');button.className='button ghost';button.textContent='查看';button.addEventListener('click',()=>{logsSelected=row;$('logsDetailText').textContent=JSON.stringify(row,null,2);$('logsTrace').disabled=!(row.requestId||row.aiRequestId||row.operationId||row.jobId);$('logsDetail').showModal()});td.append(button);tr.append(td);$('logsRows').append(tr)});
      if(!result.records.length){const tr=document.createElement('tr');const td=cell(tr,'当前筛选暂无日志');td.colSpan=7;$('logsRows').append(tr)}
      $('logsPage').textContent=result.total?(logsOffset+1)+'–'+Math.min(logsOffset+50,result.total)+' / '+result.total:'0 条';
      $('logsPrevious').disabled=logsOffset===0;$('logsNext').disabled=logsOffset+50>=logsTotal;
    }catch(error){if(generation!==logsGeneration)return;$('logsError').textContent=error.message;$('logsNotice').textContent='未能读取日志，暂无有效统计。';$('logsSummary').replaceChildren();$('logsGroups').replaceChildren();$('logsRows').replaceChildren();$('logsPage').textContent='';}
  }
  $('logsFilters').addEventListener('submit',event=>{event.preventDefault();logsOffset=0;loadDiagnostics()});
  $('logsRefresh').addEventListener('click',()=>{logsOffset=0;loadDiagnostics()});
  $('logsReset').addEventListener('click',()=>{$('logsFilters').reset();logsOffset=0;loadDiagnostics()});
  $('logsPrevious').addEventListener('click',()=>{logsOffset=Math.max(0,logsOffset-50);loadDiagnostics()});
  $('logsNext').addEventListener('click',()=>{logsOffset+=50;loadDiagnostics()});
  $('logsTrace').addEventListener('click',()=>{if(!logsSelected)return;$('logsRequest').value=logsSelected.requestId||logsSelected.aiRequestId||logsSelected.operationId||logsSelected.jobId;$('logsLevel').value='all';$('logsService').value='all';$('logsCode').value='';logsOffset=0;$('logsDetail').close();loadDiagnostics()});
`;
