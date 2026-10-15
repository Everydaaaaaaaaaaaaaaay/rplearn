const reviewData=JSON.parse(document.getElementById('quality-data').textContent);
const labels={7:'初一',8:'初二',9:'初三',10:'高一',11:'高二',12:'高三'};
Object.assign(labels,reviewData.levelLabels||{});
const el=id=>document.getElementById(id),escapeText=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let activeGrade=7,activeFamily='reading_choice';const drafts={};
const titleState=cell=>cell.state==='author_prototype_source_mode_pending'?'原型·模式待核':cell.groupId?'可预览':!cell.observed?'暂无证据':cell.state.startsWith('existing_simulated')?'来源待核':'待补题';
function select(grade,family){activeGrade=grade;activeFamily=family;if(!reviewData.cells.find(c=>c.grade===grade&&c.family===family).observed)el('show-unknown').checked=true;render();}
function makeButton(label,pressed,fn){const b=document.createElement('button');b.type='button';b.textContent=label;b.setAttribute('aria-pressed',String(pressed));b.onclick=fn;return b;}
function inputFor(g,q){
 const saved=drafts[g.id]||{};
 if(q.options.length)return q.options.map(([letter,text])=>'<label class="choice"><input type="radio" name="'+q.number+'" value="'+letter+'" '+(saved[q.number]===letter?'checked':'')+'><span>'+letter+'. '+(q.optionImages?'<img class="option-image" src="'+escapeText(q.optionImages[letter].src)+'" alt="'+escapeText(q.optionImages[letter].alt)+'" width="300" height="180">':escapeText(text))+'</span></label>').join('');
 if(q.knownForms){const key=String(q.number)+'.1';return '<input class="short-answer" type="text" name="'+key+'" aria-label="'+escapeText(q.stem)+'" value="'+escapeText(saved[key]||'')+'" autocomplete="off" lang="en">';}
 const parts=q.parts||[{label:q.stem}];return parts.map((part,i)=>{const key=String(q.number)+'.'+(i+1);return (part.opening?'<p class="fixed" lang="en">'+escapeText(part.opening)+'</p>':'')+'<label class="written">'+escapeText(part.label)+'<textarea name="'+key+'" rows="'+(g.responseMode==='writing_review'?9:3)+'" lang="en">'+escapeText(saved[key]||'')+'</textarea></label>';}).join('');
}
function mediaReady(g){const images=[...el('student').querySelectorAll('img')],expected=[...(g.requiredPassageImages||[]),...g.questions.flatMap(q=>q.optionImages?Object.values(q.optionImages):[])],count=(g.requiredImageAssets?.length||0)+(g.requiredPassageImages?.length||0);return expected.length===count&&images.length===count&&images.every((img,i)=>img.complete&&img.naturalWidth>0&&img.getAttribute('src')===expected[i].src&&img.getAttribute('alt')===expected[i].alt);}
function render(){
 const cell=reviewData.cells.find(c=>c.grade===activeGrade&&c.family===activeFamily),g=reviewData.groups[cell.groupId];
 el('grades').innerHTML='';reviewData.grades.forEach(grade=>el('grades').append(makeButton(labels[grade],grade===activeGrade,()=>select(grade,activeFamily))));
 el('families').innerHTML='';reviewData.cells.filter(c=>c.grade===activeGrade&&(c.observed||el('show-unknown').checked)).forEach(c=>el('families').append(makeButton(c.label+' · '+titleState(c),c.family===activeFamily,()=>select(activeGrade,c.family))));
 const prototypeNotice=cell.state==='author_prototype_source_mode_pending'?'作者设计原型：原样本的必要图示与角色仍缺。此处展示原创完整图题，面板结构由作者设计，不能当作原卷模式已经核证。':(g?.sourceFormNotice||'');
 el('task-title').textContent=labels[activeGrade]+' · '+cell.label;el('teacher').hidden=true;el('teacher-content').innerHTML='';el('notice').textContent='';
 const instruction=g?.instruction||(g&&['reading','cloze'].includes(g.kind)?'阅读短文，从'+(g.kind==='cloze'?'每空':'每题')+'所给的'+(g.questions[0].options.length===3?'三个':'四个')+'选项中选出最佳答案。':'');
 el('task-instruction').textContent=instruction;el('task-instruction').hidden=!instruction;
 el('answer-toggle').hidden=!g;el('reset').hidden=!g;el('answer-toggle').textContent='查看参考与解析';
 if(!g){el('student').innerHTML='<p class="empty">'+(!cell.observed?'当前样本还不足以确认这个年级的此类题型，暂不据此编题。':cell.state.startsWith('existing_simulated')?'已有模拟来源参照稿，普通学校样本的完整形式仍待核对；本格暂未交付。':'这个年级已有此类题的样本证据，完整原创代表题仍在补充。')+'</p>';el('source-note').textContent='';return;}
 const questions=g.questions.map(q=>'<fieldset><legend>'+q.number+'. '+(q.stemHtml||escapeText(q.stem))+'</legend>'+inputFor(g,q)+'</fieldset>').join('');
 el('notice').textContent=prototypeNotice;
 el('student').innerHTML=g.studentBeforeHtml!==undefined&&g.studentBeforeHtml!==null?g.studentBeforeHtml+'<form id="responses">'+questions+'</form>'+g.studentAfterHtml:g.passageHtml+'<form id="responses">'+questions+'</form>';
 const save=e=>{if(e.target.name){(drafts[g.id]||=(Object.create(null)))[e.target.name]=e.target.value;}};el('responses').oninput=save;el('responses').onchange=save;el('responses').onsubmit=e=>e.preventDefault();
 el('source-note').innerHTML='<p>完整作者稿：<a href="../../Research/GuYouJi-English-Benchmark/'+encodeURI(g.candidate.path)+'" target="_blank" rel="noopener">'+escapeText(g.id)+'</a></p><p>来源形式参照：'+escapeText((g.anchor_group_ids||[]).join(' / ')||'原卷未配对写作任务，详见作者稿')+'</p>';
 el('answer-toggle').onclick=()=>{if(!mediaReady(g)){el('notice').textContent='必要图片尚未完整显示，请等待加载完成后查看参考。';return;}el('notice').textContent=prototypeNotice;el('teacher').hidden=!el('teacher').hidden;el('answer-toggle').textContent=el('teacher').hidden?'查看参考与解析':'收起参考与解析';
  el('teacher-content').innerHTML=g.questions.map(q=>'<div class="answer"><strong>'+q.number+'. '+(q.answer?'作者参考 '+escapeText(q.answer):q.knownForms?'作者参考形式 '+escapeText(q.knownForms.join(' / ')):q.referenceAnswers?'作者参考表达 '+escapeText(q.referenceAnswers.join(' / ')):'完整表达：按任务要点复核')+'</strong><p>'+escapeText(q.rationale||'')+'</p></div>').join('')+(g.reviewHtml||'');};
 el('reset').onclick=()=>{delete drafts[g.id];render();};
}
el('coverage').textContent=reviewData.current_scope_policy?'当前范围展示 '+reviewData.preview_cells+' 道完整大题；需AI判断的主观题已暂停，不计当前覆盖缺口。':'当前 '+(reviewData.source_form_representative_cells||reviewData.preview_cells)+' 个年级/题型格有样本完整形式参照；另 '+(reviewData.prototype_source_mode_pending_cells||0)+' 个设计原型待核源图，其余证据状态逐项列明。';
const families=[...new Set(reviewData.cells.map(c=>c.family))];
el('matrix-body').innerHTML=families.map(f=>'<tr><th scope="row">'+escapeText(reviewData.cells.find(c=>c.family===f).label)+'</th>'+reviewData.grades.map(grade=>{const c=reviewData.cells.find(c=>c.grade===grade&&c.family===f);return '<td><button type="button" data-grade="'+grade+'" data-family="'+f+'" class="'+(c.state==='author_prototype_source_mode_pending'?'pending':c.groupId?'ready':!c.observed?'unknown':'pending')+'">'+titleState(c)+'</button></td>';}).join('')+'</tr>').join('');
el('matrix-body').onclick=e=>{const b=e.target.closest('button[data-grade]');if(b)select(reviewData.grades.find(g=>String(g)===b.dataset.grade),b.dataset.family);};
el('show-unknown').onchange=()=>{if(!el('show-unknown').checked&&!reviewData.cells.find(c=>c.grade===activeGrade&&c.family===activeFamily).observed)activeFamily='reading_choice';render();};render();
