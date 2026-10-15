const items=JSON.parse(document.getElementById('showcase-data').textContent);
const states=items.map(()=>({answers:{},submitted:false}));let active=0;
const byId=id=>document.getElementById(id);
const escapeHtml=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const docLink=ref=>'<a href="../../Research/GuYouJi-English-Benchmark/'+encodeURI(ref.path)+'" target="_blank" rel="noopener">'+escapeHtml(ref.path)+'</a>';
const grades=[...new Set(items.map(g=>g.grade))];
const kinds=[['reading','阅读理解'],['cloze','完形填空'],['language','语言运用'],['matching','活动配对'],['insertion','段落衔接'],['open','开放作答'],['writing','邮件写作'],['continuation','读后续写']];
const normalizeForm=s=>String(s).trim().replace(/\s+/g,' ').toLowerCase();
const exceedsLimit=(q,value)=>Boolean(q.maxWords&&String(value).trim().split(/\s+/).length>q.maxWords);
const matchesForm=(q,value)=>!exceedsLimit(q,value)&&q.knownForms.some(form=>normalizeForm(form)===normalizeForm(value));
const partKey=(q,i)=>String(q.number)+'.'+String(i+1);
const isOpen=g=>['open_review','writing_review'].includes(g.responseMode);
const mediaReady=()=>{const g=items[active],images=[...document.querySelectorAll('#quiz img.option-image')],graphs=[...document.querySelectorAll('#passage img.passage-image')],required=g.requiredPassageImages||[];return images.length===(g.requiredImageAssets?.length||0)&&images.every(img=>img.complete&&img.naturalWidth>0)&&graphs.length===required.length&&graphs.every((img,i)=>img.complete&&img.naturalWidth>0&&img.getAttribute('src')===required[i].src&&img.getAttribute('alt')===required[i].alt);};
const mediaPendingMessage=()=>items[active].requiredPassageImages?.length?'图表尚未完整显示，暂不能核对本组。请等待加载完成或刷新页面。':'四幅图片尚未完整显示，暂不能核对本组。请等待加载完成或刷新页面。';
const completed=(g,q,s)=>isOpen(g)?q.parts.every((p,i)=>String(s.answers[partKey(q,i)]||'').trim()):Boolean(String(s.answers[q.number]||'').trim());
function duplicates(g,s){if(!g.sharedRule?.atMostOnce)return [];const values=g.questions.map(q=>s.answers[q.number]).filter(Boolean);return [...new Set(values.filter((v,i)=>values.indexOf(v)!==i))];}
function select(grade,kind){let index=items.findIndex(g=>g.grade===grade&&g.kind===kind);if(index<0)index=items.findIndex(g=>g.grade===grade);active=index;render();}
grades.forEach(grade=>{const b=document.createElement('button');b.type='button';b.textContent=items.find(g=>g.grade===grade).label;b.addEventListener('click',()=>select(grade,items[active].kind));byId('grades').append(b);});
function updateCounts(){const g=items[active],s=states[active];g.questions.forEach(q=>{const node=byId('count-'+q.number);if(!node)return;const values=q.parts.map((p,i)=>s.answers[partKey(q,i)]||'');const counts=values.map(v=>(v.match(/[A-Za-z0-9]+(?:['’\-][A-Za-z0-9]+)*/g)||[]).length);node.textContent=(q.parts.length>1?'两段新增词数：'+counts.join(' + ')+' = '+counts.reduce((a,b)=>a+b,0):'当前输入词数：'+counts[0])+(g.wordTarget?'；题面要求约'+g.wordTarget+'词。仅作输入计量，不设硬容差或自动扣分。':'；仅记录输入，不自动评判内容或语言。');});}
function render(){
 const g=items[active],s=states[active],free=g.responseMode==='reference_form',open=isOpen(g);
 [...byId('grades').children].forEach((b,i)=>b.setAttribute('aria-pressed',String(grades[i]===g.grade)));
 byId('types').innerHTML='';kinds.filter(([kind])=>items.some(item=>item.grade===g.grade&&item.kind===kind)).forEach(([kind,label])=>{const b=document.createElement('button');b.type='button';b.textContent=label;b.setAttribute('aria-pressed',String(kind===g.kind));b.onclick=()=>select(g.grade,kind);byId('types').append(b);});
 const siblings=items.map((item,index)=>({item,index})).filter(({item})=>item.grade===g.grade&&item.kind===g.kind);
 byId('groups').hidden=siblings.length<2;byId('groups').innerHTML='';siblings.forEach(({item,index},i)=>{const b=document.createElement('button');b.type='button';b.textContent='第'+(i+1)+'组 · '+item.typeLabel+'（'+item.questions.length+'处）';b.setAttribute('aria-pressed',String(index===active));b.onclick=()=>{active=index;render();};byId('groups').append(b);});
 byId('grade-title').textContent=g.label+' · '+g.typeLabel;
 byId('instruction').textContent=g.instruction||('阅读短文，从'+(g.kind==='cloze'?'每空':'每题')+'所给的'+(g.questions[0].options.length===3?'三个':'四个')+'选项中选出最佳答案。');
 byId('passage').innerHTML=g.passageHtml;
 byId('quiz').innerHTML=g.questions.map(q=>{
  const value=s.answers[q.number]||'',matched=free&&value&&matchesForm(q,value);
  let response,explanation;
  if(open){response=q.parts.map((part,i)=>'<div class="open-response">'+(part.opening?'<p lang="en" class="fixed-opening">给定段首：'+escapeHtml(part.opening)+'</p>':'')+'<label class="text-response"><span>'+escapeHtml(part.label)+'</span><textarea class="answer-field" rows="'+(g.responseMode==='writing_review'?9:3)+'" name="q'+partKey(q,i)+'" aria-label="'+escapeHtml(part.label)+'" autocomplete="off" spellcheck="false" lang="en" '+(s.submitted?'disabled':'')+'>'+escapeHtml(s.answers[partKey(q,i)]||'')+'</textarea></label></div>').join('')+'<p class="footnote" id="count-'+q.number+'"></p>';explanation='<strong>已保存作答，需按下方完整作者依据复核。</strong> 本页不自动判正确、定档或打分。';}
  else if(free){response='<label class="text-response '+(s.submitted?(matched?'matched':'unmatched'):'')+'"><input class="answer-field" type="text" aria-label="第'+q.number+'空" name="q'+q.number+'" value="'+escapeHtml(value)+'" autocomplete="off" spellcheck="false" lang="en" '+(s.submitted?'disabled':'')+'></label>';explanation='<strong>作者参考：'+escapeHtml(q.knownForms.join(' / '))+'</strong> · '+(value?(matched?'与参考形式匹配':exceedsLimit(q,value)?'超过本空明确要求的'+q.maxWords+'词；请修改响应形式':'未匹配参考集合，请结合解析复核；不自动判错'):'未作答');}
  else {response=q.options.map(([key,text])=>'<label class="'+(s.submitted?(key===q.answer?'correct':value===key?'wrong':''):'')+'"><input type="radio" name="q'+q.number+'" value="'+key+'" '+(value===key?'checked':'')+' '+(s.submitted?'disabled':'')+'><span class="option-content" lang="en">'+key+'. '+(q.optionImages?'<img class="option-image" src="'+escapeHtml(q.optionImages[key].src)+'" alt="'+escapeHtml(q.optionImages[key].alt)+'" width="300" height="180">':escapeHtml(text))+'</span></label>').join('');explanation='<strong>作者参考 '+q.answer+'</strong> · '+(value?(value===q.answer?'与参考匹配':'你的选择：'+escapeHtml(value)):'未作答');}
  return '<fieldset><legend>'+q.number+'. '+(q.stemHtml||escapeHtml(q.stem))+'</legend>'+response+(s.submitted?'<div class="explanation"><p>'+explanation+'</p><div>'+escapeHtml(q.rationale)+'</div></div>':'')+'</fieldset>';
 }).join('');
 const saveAnswer=e=>{if(!e.target.name)return;s.answers[e.target.name.slice(1)]=e.target.value;byId('result').textContent='';updateCounts();};byId('quiz').onchange=saveAnswer;byId('quiz').oninput=saveAnswer;
 byId('submit').hidden=s.submitted;byId('reveal').hidden=s.submitted;byId('reveal').textContent=open?'查看参考与评分要求':'直接看答案';
 if(s.submitted){const attempted=g.questions.filter(q=>completed(g,q,s)).length;const right=open?null:g.questions.filter(q=>free?matchesForm(q,s.answers[q.number]||''):s.answers[q.number]===q.answer).length;const repeated=duplicates(g,s);
  byId('result').textContent=open?'已完整填写 '+attempted+'/'+g.questions.length+' 个作答任务。下方为作者参考及暂定评分依据，未自动给分。':free?'已作答 '+attempted+'/'+g.questions.length+' 空，'+right+' 空与作者参考形式匹配（忽略大小写）。未匹配不自动判错，参考集合尚未认证穷尽。':g.sharedRule?'已作答 '+attempted+'/'+g.questions.length+' 处，'+right+' 处与作者参考匹配。'+(repeated.length?'候选'+repeated.join('、')+'重复使用，整组规则不合。':'共享候选未重复使用。'):'已作答 '+attempted+'/'+g.questions.length+' 题，答对 '+right+' 题。';
 }else byId('result').textContent=open?'填写完整回答后提交。开放表达有多种合理答案，本页不自动打分。':free?'填入完整响应；本页只核对作者参考形式，未匹配答案需结合解析复核。':'';
 let review=byId('full-review');if(!review){review=document.createElement('details');review.id='full-review';review.className='full-author-review';byId('result').after(review);}review.hidden=!s.submitted||!g.reviewHtml;review.innerHTML='<summary>展开完整作者依据、变体与评分要求</summary><div class="author-review">'+(g.reviewHtml||'')+'</div>';
 const sourceNote=g.sourceFormReference?'<p>形式/评分参考（未配对）：'+docLink(g.sourceFormReference.catalogue)+'，源任务'+g.sourceFormReference.task_number+'</p>':'<p>来源锚组：<code>'+escapeHtml(g.anchor_group_ids.join(' / '))+'</code></p>';
 byId('provenance').innerHTML='<p>'+escapeHtml(g.focus)+'</p><p>作者版本：'+docLink(g.candidate)+'</p><p>创作时规格：'+docLink(g.specification_at_authoring)+'</p>'+sourceNote+'<p>完整作者检查：'+docLink(g.author_check)+'</p><p>当前样本规则：<a href="../../Research/GuYouJi-English-Benchmark/FirstRelease/PracticalAuthoringStandard-v0.54.md" target="_blank" rel="noopener">标准0.54</a> · <a href="../../Research/GuYouJi-English-Benchmark/FirstRelease/SampleBasedModePolicy-v0.2.md" target="_blank" rel="noopener">年级、题型与体量证据</a></p><p>全部作者稿：<a href="../../Research/GuYouJi-English-Benchmark/FirstRelease/ReviewPackage-v0.29.md" target="_blank" rel="noopener">完整审阅包</a>。本页选定样题不表示年级全部题型覆盖。</p>';
 byId('quiz').onsubmit=e=>e.preventDefault();updateCounts();
}
byId('submit').onclick=()=>{if(!mediaReady()){byId('result').textContent=mediaPendingMessage();return;}const g=items[active],s=states[active];const missing=g.questions.filter(q=>!completed(g,q,s));if(missing.length){byId('result').textContent='还有 '+missing.length+' 个任务未完整作答：'+missing.map(q=>q.number).join('、')+'。'+(g.kind==='continuation'?'两段续写须分别填写两段；':'')+'也可先查看参考。';return;}const repeated=duplicates(g,s);if(repeated.length){byId('result').textContent='候选 '+repeated.join('、')+' 重复使用，本题明确每项最多一次。请检查整组配对。';return;}s.submitted=true;render();};
byId('reveal').onclick=()=>{if(!mediaReady()){byId('result').textContent=mediaPendingMessage();return;}states[active].submitted=true;render();};
byId('reset').onclick=()=>{states[active]={answers:{},submitted:false};render();};render();
