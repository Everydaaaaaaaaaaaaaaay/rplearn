const reviewData=JSON.parse(document.getElementById('quality-data').textContent);
const labels={7:'初一',8:'初二',9:'初三',10:'高一',11:'高二',12:'高三'};
Object.assign(labels,reviewData.levelLabels||{});
const el=id=>document.getElementById(id),escapeText=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let activeGrade=7,activeFamily='reading_choice';const drafts={},selectedVariants={};
const groupIds=cell=>cell.groupIds||(cell.groupId?[cell.groupId]:[]);
const candidateHref=reference=>'../../'+(reference.path.startsWith('build/')?'':'Research/GuYouJi-English-Benchmark/')+encodeURI(reference.path);
const titleState=cell=>cell.state==='paused_requires_semantic_adjudication'?'旧稿暂缓·待补代表':cell.state==='source_observed_deterministic_admission_pending'?'待审判分':cell.state==='author_prototype_source_mode_pending'?'原型·模式待核':cell.groupId?groupIds(cell).length+'稿 / 目标3稿'+(cell.pendingSpecificModes?.length?'；另'+cell.pendingSpecificModes.length+'模式待补':''):!cell.observed?'暂无证据':cell.state.startsWith('existing_simulated')?'来源待核':'待补题';
function select(grade,family){activeGrade=grade;activeFamily=family;if(!reviewData.cells.find(c=>c.grade===grade&&c.family===family).observed)el('show-unknown').checked=true;render();}
function selectGrade(grade){const current=reviewData.cells.find(c=>c.grade===grade&&c.family===activeFamily),available=reviewData.cells.find(c=>c.grade===grade&&c.groupId);select(grade,current?.groupId?activeFamily:available?.family||activeFamily);}
function makeButton(label,pressed,fn){const b=document.createElement('button');b.type='button';b.textContent=label;b.setAttribute('aria-pressed',String(pressed));b.onclick=fn;return b;}
function inputFor(g,q){
 const saved=drafts[g.id]||{};
 if(g.fixedSharedBank)return '<select class="short-answer" name="'+q.number+'" aria-label="'+escapeText(q.stem)+'"><option value="">请选择</option>'+q.options.map(([letter,text])=>'<option value="'+letter+'" '+(saved[q.number]===letter?'selected':'')+'>'+(g.kind==='dialogue_ordering'?escapeText(text):letter+'. '+escapeText(text))+'</option>').join('')+'</select>';
 if(q.options.length){
  const choices=q.options.map(([letter,text])=>'<label class="choice"><input type="radio" name="'+q.number+'" value="'+letter+'" '+(saved[q.number]===letter?'checked':'')+'><span>'+letter+'. '+(q.optionImages?'<img class="option-image" src="'+escapeText(q.optionImages[letter].src)+'" alt="'+escapeText(q.optionImages[letter].alt)+'" width="'+(q.optionImages[letter].width||300)+'" height="'+(q.optionImages[letter].height||180)+'">':escapeText(text))+'</span></label>').join('');
  const compact=q.optionImages&&q.options.length<=3&&Object.values(q.optionImages).every(image=>image.width<=300&&image.height<=300);
  return compact?'<div class="picture-choices" style="--picture-choice-count:'+q.options.length+'">'+choices+'</div>':choices;
 }
 if(q.acceptedAnswers||q.knownForms){const key=String(q.number)+'.1';return '<input class="short-answer" type="text" name="'+key+'" aria-label="'+escapeText(q.stem)+'" value="'+escapeText(saved[key]||'')+'" autocomplete="off" lang="en">';}
 const parts=q.parts||[{label:q.stem}];return parts.map((part,i)=>{const key=String(q.number)+'.'+(i+1);return (part.opening?'<p class="fixed" lang="en">'+escapeText(part.opening)+'</p>':'')+'<label class="written">'+escapeText(part.label)+'<textarea name="'+key+'" rows="'+(g.responseMode==='writing_review'?9:3)+'" lang="en">'+escapeText(saved[key]||'')+'</textarea></label>';}).join('');
}
function mediaReady(g){const images=[...el('student').querySelectorAll('img')],expected=[...(g.requiredPassageImages||[]),...g.questions.flatMap(q=>q.optionImages?Object.values(q.optionImages):[])],count=(g.requiredImageAssets?.length||0)+(g.requiredPassageImages?.length||0),audio=[...el('student').querySelectorAll('audio')],tracks=g.requiredAudioAssets||[];return expected.length===count&&images.length===count&&images.every((img,i)=>img.complete&&img.naturalWidth>0&&img.getAttribute('src')===expected[i].src&&img.getAttribute('alt')===expected[i].alt)&&audio.length===tracks.length&&audio.every((a,i)=>!a.error&&a.readyState>=1&&Number.isFinite(a.duration)&&a.duration>0&&a.getAttribute('src')===tracks[i].src);}
function closedSelectionComparison(questions,saved={}){
 if(!Array.isArray(questions)||!questions.length)return {available:false,reason:'没有完整题组可核对。'};
 const numbers=new Set();
 for(const q of questions){
  if(!Number.isInteger(q.number)||numbers.has(q.number)||!Array.isArray(q.options)||q.options.length<2)return {available:false,reason:'此组包含未封闭的填写答案，暂不自动核对。'};
  numbers.add(q.number);
  const letters=q.options.map(o=>Array.isArray(o)?o[0]:null);
  if(letters.some(l=>typeof l!=='string'||!l)||new Set(letters).size!==letters.length||typeof q.answer!=='string'||!letters.includes(q.answer))return {available:false,reason:'参考与候选尚未完整绑定，暂不核对。'};
  const chosen=saved[q.number]||'';
  if(chosen&&!letters.includes(chosen))return {available:false,reason:'所选答案不在当前候选中，请重新填写。'};
 }
 const rows=questions.map(q=>{const chosen=saved[q.number]||'';return {number:q.number,chosen,reference:q.answer,state:!chosen?'unanswered':chosen===q.answer?'match':'different'};});
 return {available:true,total:rows.length,matched:rows.filter(r=>r.state==='match').length,different:rows.filter(r=>r.state==='different').length,unanswered:rows.filter(r=>r.state==='unanswered').length,rows};
}
function selectionSetComparison(questions,saved={}){
 const base=closedSelectionComparison(questions,saved);
 if(!base.available)return base;
 const sets=new Map();
 for(const q of questions){
  const c=q.selectionSet;
  if(!c||c.version!==1||typeof c.id!=='string'||!c.id||c.order!=='either'||c.distinct!==true||c.localMatchingRule!=='distinct_correct_options_once'||!Array.isArray(c.positions)||c.positions.length<2||new Set(c.positions).size!==c.positions.length||!c.positions.every(Number.isInteger)||!Array.isArray(c.correct)||c.correct.length!==c.positions.length||new Set(c.correct).size!==c.correct.length||!c.correct.every(k=>q.options.some(([label])=>label===k))||!c.positions.includes(q.number))return {available:false,reason:'多选提示的完整响应、无序集合或不重复规则未绑定。'};
  const prior=sets.get(c.id)||[];prior.push(q);sets.set(c.id,prior);
 }
 const rows=[],selectionConflicts=[];
 for(const [id,qs] of sets){
  const c=qs[0].selectionSet;
  if(qs.length!==c.positions.length||!c.positions.every((n,i)=>qs[i]?.number===n)||qs.some((q,i)=>JSON.stringify(q.selectionSet)!==JSON.stringify(c)||JSON.stringify(q.options)!==JSON.stringify(qs[0].options)||q.answer!==c.correct[i]))return {available:false,reason:'多选提示被截断、重排或候选集合不一致，暂不核对。'};
  const used=new Set();
  for(const q of qs){
   const chosen=saved[q.number]||'',duplicate=chosen&&used.has(chosen);
   if(chosen)used.add(chosen);
   if(duplicate)selectionConflicts.push({id,number:q.number,chosen});
   rows.push({number:q.number,chosen,reference:c.correct.join(' / ')+'（'+c.positions.length+'项，顺序任意）',state:!chosen?'unanswered':!duplicate&&c.correct.includes(chosen)?'match':'different'});
  }
 }
 return {available:true,total:rows.length,matched:rows.filter(r=>r.state==='match').length,different:rows.filter(r=>r.state==='different').length,unanswered:rows.filter(r=>r.state==='unanswered').length,review:0,selectionConflicts,rows};
}
function normalizeFill(value,protocol){
 if(typeof value!=='string')return null;
 const text=value.trim();
 if(protocol==='latin_word_v1')return /^[A-Za-z]+$/.test(text)?text.toUpperCase():null;
 if(protocol==='english_phrase_v1')return /^[A-Za-z]+(?:['’-][A-Za-z]+)*(?:\s+[A-Za-z]+(?:['’-][A-Za-z]+)*)*$/.test(text)?text.replace(/’/g,"'").replace(/\s+/g,' ').toUpperCase():null;
 if(protocol==='source_excerpt_v1'){
  const excerpt=text.replace(/[０-９]/g,c=>String(c.charCodeAt(0)-0xFF10)).replace(/[‐‑–−]/g,'-').replace(/’/g,"'");
  return /^[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*(?:\s+[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*)*$/.test(excerpt)?excerpt.replace(/\s+/g,' ').toUpperCase():null;
 }
 if(protocol==='source_list_v1'){
  // This contract is only for a bounded list of single-word source categories.
  // Keep malformed punctuation unknown; never strip punctuation from other fills.
  return /^[A-Za-z]+(?:(?:\s*,\s*|\s+)[A-Za-z]+)*$/.test(text)?text.toUpperCase().split(/\s*,\s*|\s+/).sort().join(' '):null;
 }
 if(protocol==='uk_postcode_v1'){
  const code=text.toUpperCase().replace(/[０-９]/g,c=>String(c.charCodeAt(0)-0xFF10));
  return /^[A-Z]{1,2}[0-9][A-Z0-9]?\s*[0-9][A-Z]{2}$/.test(code)?code.replace(/\s/g,''):null;
 }
 if(['metric_length_v1','sterling_amount_v1'].includes(protocol)){
  const form=text.replace(/[０-９]/g,c=>String(c.charCodeAt(0)-0xFF10)).replace(/．/g,'.').replace(/，/g,',').replace(/[‐‑–−]/g,'-').replace(/\s+/g,' ').toUpperCase();
  return /^[A-Z0-9£½¾][A-Z0-9£½¾.,/ -]*$/.test(form)?form:null;
 }
 if(protocol==='clock_hour_v1'){
  const clock=text.replace(/[０-９]/g,c=>String(c.charCodeAt(0)-0xFF10)).replace(/：/g,':').replace(/．/g,'.');
  return /^(?:[0-9]{1,2}(?:[:.][0-9]{2})?|[A-Za-z]+)$/.test(clock)?clock.toUpperCase():null;
 }
 if(protocol==='ascii_integer_v1'){
  const digits=text.replace(/[０-９]/g,c=>String(c.charCodeAt(0)-0xFF10));
  return /^[0-9]+$/.test(digits)?digits.replace(/^0+(?=\d)/,''):null;
 }
 if(protocol==='small_count_v1'){
  const count=text.replace(/[０-９]/g,c=>String(c.charCodeAt(0)-0xFF10));
  return /^[0-9]+$/.test(count)?count.replace(/^0+(?=\d)/,''):/^[A-Za-z]+$/.test(count)?count.toUpperCase():null;
 }
 return null;
}
function formNumber(value){
 if(!/^[0-9]+(?:\.[0-9]{1,6})?$/.test(value))return null;
 const parts=value.split('.'),denominator=10**(parts[1]?.length||0),numerator=Number(parts.join(''));
 return Number.isSafeInteger(numerator)&&numerator<=1e9?[numerator,denominator]:null;
}
function metricLength(value){
 if(typeof value!=='string')return null;
 const m=value.match(/^(\d+(?:\.\d{1,6})?|\d+\/\d+|½|¾)\s*(M|METRE|METRES|METER|METERS|CM|CMS|CENTIMETRE|CENTIMETRES|CENTIMETER|CENTIMETERS)(?:\s+(WIDE|HIGH|DEEP))?$/);
 if(!m)return null;let fraction;
 if(m[1]==='½')fraction=[1,2];else if(m[1]==='¾')fraction=[3,4];else if(m[1].includes('/')){fraction=m[1].split('/').map(Number);if(!fraction.every(n=>Number.isSafeInteger(n)&&n<=1e6)||fraction[1]===0)return null;}else fraction=formNumber(m[1]);
 if(!fraction)return null;
 return {numerator:fraction[0],denominator:fraction[1]*(m[2].startsWith('C')?100:1),axis:m[3]||null};
}
function sterlingPence(value){
 if(typeof value!=='string')return null;
 const m=value.match(/^£?\s*(\d+|[1-9]\d{0,2}(?:,\d{3})+)(?:\.(\d{1,2}))?(?:\s+(?:POUND|POUNDS|GBP))?$/);
 if(!m)return null;const pence=Number(m[1].replace(/,/g,''))*100+Number((m[2]||'').padEnd(2,'0'));
 return Number.isSafeInteger(pence)&&pence<=1e11?pence:null;
}
function formWordCount(value,contract){
 return ['metric_length_v1','sterling_amount_v1'].includes(contract.normalization)?(value.match(/[A-Z]+(?:-[A-Z]+)*/g)||[]).length:value.split(' ').length;
}
function clockMinutes(value){
 const names=['ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','TEN','ELEVEN','TWELVE'];
 const word=names.indexOf(value);if(word>=0)return (word+1)*60;
 if(typeof value!=='string')return null;
 const m=value.match(/^([0-9]{1,2})(?:[:.]([0-9]{2}))?$/);
 if(!m)return null;const hour=Number(m[1]),minute=Number(m[2]||0);
 return hour>=1&&hour<=12&&minute<60?hour*60+minute:null;
}
function smallCount(value){
 const names=['ZERO','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','TEN','ELEVEN','TWELVE','THIRTEEN','FOURTEEN','FIFTEEN','SIXTEEN','SEVENTEEN','EIGHTEEN','NINETEEN','TWENTY'];
 const word=names.indexOf(value);if(word>=0)return word;
 return typeof value==='string'&&/^[0-9]+$/.test(value)?value:null;
}
function answerComparison(questions,saved={}){
 if(Array.isArray(questions)&&questions.some(q=>q.fillPair))return fillPairComparison(questions,saved);
 if(Array.isArray(questions)&&questions.some(q=>q.selectionSet))return selectionSetComparison(questions,saved);
 if(!Array.isArray(questions)||!questions.length)return {available:false,reason:'没有完整题组可核对。'};
 const onceBank=questions.some(q=>q.bankReuse!==undefined),knownBankRoots=new Map(),bankEntries=new Set();
 if(onceBank){
  for(const q of questions){
   const root=normalizeFill(q.bankEntry,'english_phrase_v1');
   if(q.bankReuse!=='once'||root===null||bankEntries.has(root)||q.fillMarking?.normalization!=='english_phrase_v1'||!Array.isArray(q.acceptedAnswers))return {available:false,reason:'完整词库的复用规则或根项对应尚未绑定。'};
   bankEntries.add(root);
   for(const value of q.acceptedAnswers){const form=normalizeFill(value,'english_phrase_v1');if(form===null||knownBankRoots.has(form)&&knownBankRoots.get(form)!==q.bankEntry)return {available:false,reason:'同一参考形式对应多个词库项，暂不自动核对。'};knownBankRoots.set(form,q.bankEntry);}
  }
 }
 const rows=[],numbers=new Set();
 for(const q of questions){
  if(!Number.isInteger(q.number)||numbers.has(q.number)||!Array.isArray(q.options))return {available:false,reason:'题号或完整作答协议未绑定。'};
  numbers.add(q.number);
  if(q.options.length){
   const selection=closedSelectionComparison([q],saved);
   if(!selection.available)return selection;
   rows.push(selection.rows[0]);continue;
  }
  const contract=q.fillMarking,accepted=q.acceptedAnswers;
  if(!contract||contract.version!==1||contract.review!=='author_context_checked'||!['latin_word_v1','english_phrase_v1','source_excerpt_v1','source_list_v1','ascii_integer_v1','clock_hour_v1','small_count_v1','uk_postcode_v1','metric_length_v1','sterling_amount_v1'].includes(contract.normalization)||!['review','different'].includes(contract.unlisted)||!Array.isArray(accepted)||!accepted.length||accepted.some(a=>typeof a!=='string'||normalizeFill(a,contract.normalization)===null)||!Array.isArray(contract.rejectedAnswers))return {available:false,reason:'此组填写答案尚无完整的可接受形式与规范化协议，暂不自动核对。'};
  const formQuantity=['metric_length_v1','sterling_amount_v1'].includes(contract.normalization),formValue=formQuantity||contract.normalization==='uk_postcode_v1';
  if(formValue&&(contract.sourceBound!==true||contract.unknownSyntax!=='review'||contract.unlisted!=='review'||contract.maxWords!==3||contract.numberAllowance!=='one'))return {available:false,reason:'表单空的输入范围、限词/数字或未知格式规则未绑定。'};
  if(contract.normalization==='metric_length_v1'&&(!Number.isSafeInteger(contract.metricMillimetres)||contract.metricMillimetres<=0||contract.metricMillimetres>1e7||!['width','height'].includes(contract.dimensionAxis)||accepted.some(a=>{const p=metricLength(normalizeFill(a,contract.normalization));return p===null||p.numerator*1000!==contract.metricMillimetres*p.denominator||p.axis&&!((contract.dimensionAxis==='width'?['WIDE']:['HIGH','DEEP']).includes(p.axis));})))return {available:false,reason:'尺寸空的单位、方向或等值形式不一致。'};
  if(contract.normalization==='sterling_amount_v1'&&(!Number.isSafeInteger(contract.sterlingPence)||contract.sterlingPence<0||contract.currencyPrinted!=='£'||accepted.some(a=>sterlingPence(normalizeFill(a,contract.normalization))!==contract.sterlingPence)))return {available:false,reason:'金额空的币种、已印符号或等值形式不一致。'};
  if(contract.normalization==='source_list_v1'&&(contract.sourceBound!==true||contract.unknownSyntax!=='review'||contract.unlisted!=='review'||contract.maxWords!==3||contract.listSize!==3||contract.listOrder!=='any'||contract.listMembersDistinct!==true||accepted.some(a=>{const tokens=normalizeFill(a,'source_list_v1').split(' ');return tokens.length!==3||new Set(tokens).size!==3;})))return {available:false,reason:'三成员摘词答案的数量、不同成员或无序规则尚未完整绑定。'};
  if(contract.normalization==='source_excerpt_v1'&&(contract.sourceBound!==true||contract.unknownSyntax!=='review'||contract.unlisted!=='review'||!Number.isInteger(contract.maxWords)||contract.maxWords<1||contract.hyphenatedWordCount!=='one'))return {available:false,reason:'摘词填空的材料边界、限词或未知格式规则未绑定。'};
  if(contract.normalization==='clock_hour_v1'&&(contract.clockFrame!=='p.m.'||contract.unknownSyntax!=='review'||contract.unlisted!=='review'||contract.maxWords!==1||!Number.isInteger(contract.wholeHour)||contract.wholeHour<1||contract.wholeHour>12||accepted.some(a=>clockMinutes(normalizeFill(a,'clock_hour_v1'))!==contract.wholeHour*60)))return {available:false,reason:'时间空的单位、限词或未知格式复核规则未绑定。'};
  if(contract.normalization==='small_count_v1'&&(contract.unknownSyntax!=='review'||contract.unlisted!=='review'||contract.maxWords!==1||!Number.isInteger(contract.wholeCount)||contract.wholeCount<0||contract.wholeCount>20||!accepted.some(a=>/^[A-Za-z]+$/.test(a))||!accepted.some(a=>/^[0-9]+$/.test(a))||accepted.some(a=>String(smallCount(normalizeFill(a,'small_count_v1')))!==String(contract.wholeCount))))return {available:false,reason:'小整数空的数值、限词或未知格式复核规则未绑定。'};
  if(contract.normalization==='english_phrase_v1'&&!(contract.maxWords===null||Number.isInteger(contract.maxWords)&&contract.maxWords>0))return {available:false,reason:'单空限词规则未绑定。'};
  if(contract.minWords!==undefined&&(contract.normalization!=='english_phrase_v1'||!Number.isInteger(contract.minWords)||contract.minWords<1||contract.maxWords!==null&&contract.minWords>contract.maxWords||contract.wordCountAmbiguity!=='review'))return {available:false,reason:'最少词数或未核计词形式的处理规则尚未绑定。'};
  const forms=accepted.map(a=>normalizeFill(a,contract.normalization)),rejected=contract.rejectedAnswers.map(a=>normalizeFill(a,contract.normalization));
  if(contract.normalization==='metric_length_v1'&&rejected.some(v=>{const p=metricLength(v);return p!==null&&p.numerator*1000===contract.metricMillimetres*p.denominator&&(!p.axis||(contract.dimensionAxis==='width'?['WIDE']:['HIGH','DEEP']).includes(p.axis));})||contract.normalization==='sterling_amount_v1'&&rejected.some(v=>sterlingPence(v)===contract.sterlingPence))return {available:false,reason:'尺寸或金额的正确等值形式被列为错答，暂不核对。'};
  if(contract.requiredInitial!==undefined&&(!['latin_word_v1','english_phrase_v1'].includes(contract.normalization)||contract.maxWords!==1||typeof contract.requiredInitial!=='string'||!/^[A-Za-z]$/.test(contract.requiredInitial)||forms.some(a=>!a.startsWith(contract.requiredInitial.toUpperCase()))))return {available:false,reason:'首字母与一词答案范围未一致绑定。'};
  if(contract.requiredWord!==undefined&&(contract.normalization!=='english_phrase_v1'||typeof contract.requiredWord!=='string'||!/^[A-Za-z]+$/.test(contract.requiredWord)||forms.some(a=>!a.split(' ').includes(contract.requiredWord.toUpperCase()))))return {available:false,reason:'关键词原形与可接受答案未一致绑定。'};
  if(new Set(forms).size!==forms.length||rejected.some(a=>a===null||forms.includes(a))||contract.unlisted==='different'&&contract.normalization!=='ascii_integer_v1'||contract.maxWords&&forms.some(a=>formWordCount(a,contract)>contract.maxWords)||contract.minWords&&forms.some(a=>a.split(' ').length<contract.minWords))return {available:false,reason:'填写答案协议存在重复、冲突或未经支持的排他规则。'};
  const chosen=saved[String(q.number)+'.1']??'';
  if(typeof chosen!=='string')return {available:false,reason:'填写值格式无效。'};
  const normalized=normalizeFill(chosen,contract.normalization);
  const outsideLimit=normalized!==null&&(contract.maxWords&&formWordCount(normalized,contract)>contract.maxWords||contract.minWords&&normalized.split(' ').length<contract.minWords);
  const uncertainWordCount=normalized!==null&&contract.wordCountAmbiguity==='review'&&/['-]/.test(normalized);
  const missingKeyword=normalized!==null&&contract.requiredWord!==undefined&&!normalized.split(' ').includes(contract.requiredWord.toUpperCase());
  const wrongInitial=normalized!==null&&contract.requiredInitial!==undefined&&!normalized.startsWith(contract.requiredInitial.toUpperCase());
  const differentClock=contract.normalization==='clock_hour_v1'&&clockMinutes(normalized)!==null&&clockMinutes(normalized)!==contract.wholeHour*60;
  const differentCount=contract.normalization==='small_count_v1'&&smallCount(normalized)!==null&&String(smallCount(normalized))!==String(contract.wholeCount);
  const differentList=contract.normalization==='source_list_v1'&&normalized!==null&&(normalized.split(' ').length!==contract.listSize||new Set(normalized.split(' ')).size!==contract.listSize);
  const quantity=contract.normalization==='metric_length_v1'?metricLength(normalized):null,money=contract.normalization==='sterling_amount_v1'?sterlingPence(normalized):null;
  const sameMetric=quantity!==null&&quantity.numerator*1000===contract.metricMillimetres*quantity.denominator&&(!quantity.axis||(contract.dimensionAxis==='width'?['WIDE']:['HIGH','DEEP']).includes(quantity.axis));
  const sameMoney=money!==null&&money===contract.sterlingPence;
  const differentForm=quantity!==null&&!sameMetric||money!==null&&!sameMoney||contract.normalization==='uk_postcode_v1'&&normalized!==null&&!forms.includes(normalized);
  rows.push({number:q.number,chosen,reference:accepted.join(' / '),state:!chosen.trim()?'unanswered':forms.includes(normalized)||sameMetric||sameMoney?'match':normalized===null?(['clock_hour_v1','small_count_v1','source_excerpt_v1','source_list_v1'].includes(contract.normalization)||formValue?'review':'different'):differentForm||differentClock||differentCount||differentList||wrongInitial||rejected.includes(normalized)||missingKeyword||outsideLimit&&!uncertainWordCount||contract.unlisted==='different'?'different':'review'});
 }
 const usedBankRoots=new Map();
 if(onceBank)for(const row of rows){const root=knownBankRoots.get(normalizeFill(row.chosen,'english_phrase_v1'));if(root){const positions=usedBankRoots.get(root)||[];positions.push(row.number);usedBankRoots.set(root,positions);}}
 const bankConflicts=[...usedBankRoots].filter(([,positions])=>positions.length>1).map(([entry,numbers])=>({entry,numbers}));
 return {available:true,total:rows.length,matched:rows.filter(r=>r.state==='match').length,different:rows.filter(r=>r.state==='different').length,unanswered:rows.filter(r=>r.state==='unanswered').length,review:rows.filter(r=>r.state==='review').length,bankConflicts,rows};
}
function fillPairComparison(questions,saved={}){
 // Two response positions identify two different referents within one prompt.
 // Aliases share a member ID; they cannot earn two matches for one referent.
 const base=answerComparison(questions.map(q=>{const copy={...q};delete copy.fillPair;return copy;}),saved);
 if(!base.available)return base;
 const pairs=new Map(),conflicts=[];
 for(const q of questions){
  const c=q.fillPair;if(!c)continue;
  if(q.options.length||q.fillMarking?.normalization!=='source_excerpt_v1'||!c||c.version!==1||typeof c.id!=='string'||!c.id||c.order!=='either'||c.distinctReferents!==true||c.localMatchingRule!=='distinct_known_referents_once'||!Array.isArray(c.positions)||c.positions.length!==2||new Set(c.positions).size!==2||!c.positions.every(Number.isInteger)||!c.positions.includes(q.number)||!Array.isArray(c.members)||c.members.length!==2||c.members.some(m=>!m||typeof m!=='object')||new Set(c.members.map(m=>m.id)).size!==2)return {available:false,reason:'双答案提示的完整双响应、顺序或不同指代规则未绑定。'};
  const prior=pairs.get(c.id)||[];prior.push(q);pairs.set(c.id,prior);
 }
 for(const [id,qs]of pairs){
  const c=qs[0].fillPair;
  if(qs.length!==2||!c.positions.every((n,i)=>qs[i]?.number===n)||qs.some(q=>JSON.stringify(q.fillPair)!==JSON.stringify(c)||JSON.stringify(q.fillMarking)!==JSON.stringify(qs[0].fillMarking)||JSON.stringify(q.acceptedAnswers)!==JSON.stringify(qs[0].acceptedAnswers)))return {available:false,reason:'双答案提示被截断、重排或答案范围不一致，暂不核对。'};
  const aliases=new Map();
  for(const member of c.members){
   if(typeof member.id!=='string'||!member.id||!Array.isArray(member.forms)||!member.forms.length)return {available:false,reason:'双答案的同指合法形式尚未绑定。'};
   for(const form of member.forms){const normalized=normalizeFill(form,'source_excerpt_v1');if(normalized===null||aliases.has(normalized))return {available:false,reason:'双答案形式重复或对应多个指代，暂不核对。'};aliases.set(normalized,member.id);}
  }
  const forms=qs[0].acceptedAnswers.map(v=>normalizeFill(v,'source_excerpt_v1'));
  if(forms.length!==aliases.size||forms.some(v=>!aliases.has(v)))return {available:false,reason:'双答案同指形式与逐空接受范围不一致。'};
  const used=new Set();
  for(const q of qs){const row=base.rows.find(r=>r.number===q.number),member=aliases.get(normalizeFill(row.chosen,'source_excerpt_v1'));row.reference=c.members.map(m=>m.forms.join(' / ')).join('；')+'（两项顺序任意，同一项不重复）';if(row.state==='match'&&member){if(used.has(member)){row.state='different';conflicts.push({id,number:q.number,member});}used.add(member);}}
 }
 return {...base,matched:base.rows.filter(r=>r.state==='match').length,different:base.rows.filter(r=>r.state==='different').length,fillPairConflicts:conflicts};
}
function clearSelectionComparison(){el('selection-comparison').hidden=true;el('selection-comparison').textContent='';}
function render(){
 el('student').querySelectorAll('audio').forEach(a=>{a.onerror=null;a.pause();});
 const cell=reviewData.cells.find(c=>c.grade===activeGrade&&c.family===activeFamily),ids=groupIds(cell),variantKey=String(activeGrade)+':'+activeFamily;
 const selected=ids.includes(selectedVariants[variantKey])?selectedVariants[variantKey]:cell.groupId,g=reviewData.groups[selected];
 el('grades').innerHTML='';reviewData.grades.forEach(grade=>el('grades').append(makeButton(labels[grade],grade===activeGrade,()=>selectGrade(grade))));
 el('families').innerHTML='';reviewData.cells.filter(c=>c.grade===activeGrade&&(c.observed||el('show-unknown').checked)).forEach(c=>el('families').append(makeButton(c.label+' · '+titleState(c),c.family===activeFamily,()=>select(activeGrade,c.family))));
 const earlyNotice=['primary1','primary2'].includes(activeGrade)?'现行要求小学一二年级不进行纸笔考试；这里保留的历史纸笔形式稿仅供形式审阅，非现行年级测评标准。非纸笔闭集活动仍在补完整样本。 ':'';
 const prototypeNotice=earlyNotice+(cell.state==='author_prototype_source_mode_pending'?'作者设计原型：原样本的必要图示与角色仍缺。此处展示原创完整图题，面板结构由作者设计，不能当作原卷模式已经核证。':(g?.sourceFormNotice||''));
 el('task-title').textContent=labels[activeGrade]+' · '+cell.label;el('teacher').hidden=true;el('teacher-content').innerHTML='';el('notice').textContent='';clearSelectionComparison();
 el('variant-picker').hidden=ids.length<2;
 el('variants').innerHTML=ids.map((id,i)=>'<option value="'+escapeText(id)+'" '+(id===selected?'selected':'')+'>'+escapeText('第'+(i+1)+'稿 · '+(reviewData.groups[id].title||id))+'</option>').join('');
 el('variants').onchange=e=>{selectedVariants[variantKey]=e.target.value;render();};
 const instruction=g?.instruction||(g&&['reading','cloze'].includes(g.kind)?'阅读短文，从'+(g.kind==='cloze'?'每空':'每题')+'所给的'+(g.questions[0].options.length===3?'三个':'四个')+'选项中选出最佳答案。':'');
 el('task-instruction').textContent=instruction+(g?.formatSummary?' 完整配置：'+g.formatSummary:'');el('task-instruction').hidden=!instruction;
 el('answer-toggle').hidden=!g;el('reset').hidden=!g;el('answer-toggle').textContent='查看参考与解析';
 el('compare-selections').hidden=!g;
 const comparisonEligibility=answerComparison(g?.questions);
 el('compare-selections').disabled=!comparisonEligibility.available;
 el('compare-selections').title=comparisonEligibility.reason||'仅对照作者参考，不代表独立质量验收。';
 if(!g){el('student').innerHTML='<p class="empty">'+(cell.state==='paused_requires_semantic_adjudication'?'本格的旧完整题组已暂缓：'+escapeText(cell.pauseReason)+' 保留来源与旧稿，不截空冒充完整组；这不表示整个题型均需AI判分，符合约束的新完整代表仍可补编。':cell.pauseReason?escapeText(cell.pauseReason):!cell.observed?'当前样本还不足以确认这个年级的此类题型，暂不据此编题。':cell.state.startsWith('existing_simulated')?'已有模拟来源参照稿，普通学校样本的完整形式仍待核对；本格暂未交付。':'这个年级已有此类题的样本证据，完整原创代表题仍在补充。')+'</p>';el('source-note').textContent=(reviewData.pending_specific_modes||[]).filter(m=>m.grade===cell.grade&&m.family===cell.family&&m.remainingWholeOriginals).map(m=>m.title+'：'+m.remainingWholeOriginals+'组完整原创待补。'+m.source_gap).join('\n');return;}
 const questions=g.questions.map(q=>'<fieldset><legend>'+q.number+'. '+(q.stemHtml||escapeText(q.stem))+'</legend>'+inputFor(g,q)+'</fieldset>').join('');
 el('notice').textContent=prototypeNotice;
 el('student').innerHTML=g.studentBeforeHtml!==undefined&&g.studentBeforeHtml!==null?g.studentBeforeHtml+'<form id="responses">'+questions+'</form>'+g.studentAfterHtml:g.passageHtml+'<form id="responses">'+questions+'</form>';
 // The source has four people rows and five item columns: five assignments.
 // Radio names bind a whole item column, so a person may prepare several items.
 if(g.responseTable){
  const t=g.responseTable,form=el('responses'),printed=el('student').querySelector('table'),saved=drafts[g.id]||{};
  if(printed&&t.people.length===4&&t.columns.length===5&&g.questions.length===5){
   printed.remove();form.innerHTML='<div class="table-scroll"><table class="listening-assignment-table"><caption>'+escapeText(t.caption)+'</caption><thead><tr><th scope="col">人物 / 物品</th>'+t.columns.map((c,i)=>'<th scope="col">'+(i+1)+'. '+escapeText(c)+'</th>').join('')+'</tr></thead><tbody>'+t.people.map(([letter,name])=>'<tr><th scope="row">'+escapeText(name)+'</th>'+g.questions.map(q=>'<td><label><input type="radio" name="'+q.number+'" value="'+letter+'" aria-label="'+escapeText(q.stem+' — '+name)+'" '+(saved[q.number]===letter?'checked':'')+'></label></td>').join('')+'</tr>').join('')+'</tbody></table></div>';
  }
 }
 // Keep each single-response player beside its printed question. Bind by
 // the recorded response numbers so independent clips retain their order.
 if(['listening_short_conversation_choice','listening_word_phrase_choice','listening_sentence_choice','listening_picture_choice'].includes(g.kind)){
  const tracks=[...el('student').querySelectorAll('figure.listening-track')],fields=[...el('responses').querySelectorAll('fieldset')];
  if(tracks.length===g.questions.length&&fields.length===tracks.length&&g.requiredAudioAssets?.every((a,i)=>a.response_numbers.length===1&&a.response_numbers[0]===g.questions[i].number)){
   tracks.forEach((track,i)=>{const heading=track.previousElementSibling;if(heading?.tagName==='H3'&&['对话'+(i+1),'句子'+(i+1),'材料'+(i+1)].includes(heading.textContent.trim()))heading.remove();fields[i].querySelector('legend').after(track);});
  }
 }
 // A long section keeps each player next to the first of its printed questions.
 if(['listening_multi_question_choice','listening_dialogue_choice'].includes(g.kind)){
  const tracks=[...el('student').querySelectorAll('figure.listening-track')],fields=[...el('responses').querySelectorAll('fieldset')],assets=g.requiredAudioAssets||[];
  if(tracks.length===assets.length&&assets.flatMap(a=>a.response_numbers).join(',')===g.questions.map(q=>q.number).join(',')){
   tracks.forEach((track,i)=>{const heading=track.previousElementSibling;if(heading?.tagName==='H3'&&heading.textContent.trim()==='材料'+(i+1))heading.remove();fields[assets[i].response_numbers[0]-1].querySelector('legend').after(track);});
  }
 }
 if(g.kind==='listening_picture_true_false'){
  const pictures=[...el('student').querySelectorAll('img.passage-image')].map(img=>img.closest('figure')),tracks=[...el('student').querySelectorAll('figure.listening-track')],fields=[...el('responses').querySelectorAll('fieldset')];
  if(pictures.length===g.questions.length&&tracks.length===pictures.length&&g.requiredAudioAssets?.every((a,i)=>a.response_numbers.length===1&&a.response_numbers[0]===g.questions[i].number)){
   pictures.forEach((picture,i)=>{const heading=picture.previousElementSibling;if(heading?.tagName==='H3'&&['图片'+(i+1),'第'+(i+1)+'图'].includes(heading.textContent.trim()))heading.remove();fields[i].querySelector('legend').after(picture,tracks[i]);});
  }
 }
 if(g.kind==='listening_picture_matching'||g.pictureToEventRank){
  const pictures=[...el('student').querySelectorAll('img.passage-image')].map(img=>img.closest('figure')),fields=[...el('responses').querySelectorAll('fieldset')];
  if(pictures.length===g.questions.length){pictures.forEach((picture,i)=>{const heading=picture.previousElementSibling;if(heading?.tagName==='H3'&&['图片'+(i+1),'第'+(i+1)+'图'].includes(heading.textContent.trim()))heading.remove();fields[i].querySelector('legend').after(picture);});}
 }
 const firstParagraph=el('student').firstElementChild;
 if(firstParagraph?.tagName==='P'&&firstParagraph.textContent.trim()===instruction.trim())firstParagraph.remove();
 el('student').querySelectorAll('audio').forEach(a=>{a.onerror=()=>{if(el('student').contains(a))el('notice').textContent='必要音频无法载入，请刷新重试；本组尚不能完整作答。';};});
 const save=e=>{if(e.target.name){(drafts[g.id]||=(Object.create(null)))[e.target.name]=e.target.value;clearSelectionComparison();}};el('responses').oninput=save;el('responses').onchange=save;el('responses').onsubmit=e=>e.preventDefault();
 el('source-note').innerHTML='<p>完整作者稿：<a href="'+candidateHref(g.candidate)+'" target="_blank" rel="noopener">'+escapeText(g.id)+'</a></p><p>来源形式参照：'+escapeText((g.anchor_group_ids||[]).join(' / ')||'原卷未配对写作任务，详见作者稿')+'</p>';
 el('answer-toggle').onclick=()=>{if(!mediaReady(g)){el('notice').textContent='必要图片或音频尚未完整载入，请等待加载完成后查看参考。';return;}el('notice').textContent=prototypeNotice;el('teacher').hidden=!el('teacher').hidden;el('answer-toggle').textContent=el('teacher').hidden?'查看参考与解析':'收起参考与解析';
  el('teacher-content').innerHTML=g.questions.map(q=>'<div class="answer"><strong>'+q.number+'. '+(q.selectionSet?'作者参考集合 '+escapeText(q.selectionSet.correct.join(' / '))+'（本提示内顺序任意）':q.answer?'作者参考 '+escapeText(q.answer):q.acceptedAnswers?'可接受形式 '+escapeText(q.acceptedAnswers.join(' / ')):q.knownForms?'作者参考形式 '+escapeText(q.knownForms.join(' / ')):q.referenceAnswers?'作者参考表达 '+escapeText(q.referenceAnswers.join(' / ')):'完整表达：按任务要点复核')+'</strong><p>'+escapeText(q.rationale||'')+'</p></div>').join('')+(g.reviewHtml||'');};
 el('compare-selections').onclick=()=>{
  if(!mediaReady(g)){el('notice').textContent='必要图片或音频尚未完整载入，请等待加载完成后核对。';return;}
  const result=answerComparison(g.questions,drafts[g.id]);
  if(!result.available){el('notice').textContent=result.reason;return;}
  el('notice').textContent=prototypeNotice;
  el('selection-comparison').innerHTML='<strong>按作者参考：'+result.matched+'/'+result.total+' 项一致；'+result.different+' 项不同；'+result.unanswered+' 项未答；'+result.review+' 项待复核。</strong>'+(result.fillPairConflicts?.length?'<p>同一双答案提示内的两空须指向不同项目；同一项目的两个合法别名不重复计入。不同提示独立，未列表达仍待复核；本机一致项统计不等于原考试部分给分。</p>':'')+(result.selectionConflicts?.length?'<p>同一多选提示中重复选择不重复计入；各提示之间独立。此处按作者定义核对不同正确选项，不冒称原考试部分给分规则。</p>':'')+(result.bankConflicts?.length?'<p class="bank-conflict">词库复用冲突：'+result.bankConflicts.map(c=>escapeText(c.entry)+'（第'+c.numbers.join('、')+'空）').join('；')+'。这些作答重复使用同一词库项，整组尚未符合每项一次的规则；不据此擅自分配部分分。未列词形仍待复核，不自动猜词根。</p>':'')+'<p>本机按逐题规则核对，已列合法变体同等接受。未列词形不直接判错；待复核项不计为错误。作者自审不代表独立教研或生产判分通过。</p><ol>'+result.rows.map(r=>'<li>第'+r.number+'题：'+(r.chosen?'作答 '+escapeText(r.chosen):'未作答')+'；作者参考 '+escapeText(r.reference)+'（'+({match:'一致',different:'不同',unanswered:'未答',review:'待复核'}[r.state])+'）</li>').join('')+'</ol>';
  el('selection-comparison').hidden=false;
 };
 el('reset').onclick=()=>{delete drafts[g.id];render();};
}
el('coverage').textContent=reviewData.current_scope_policy?'当前展示 '+reviewData.preview_cells+' 道完整大题，已有稿件涉及 '+reviewData.source_form_representative_cells+' 个档位/题型格，其中 '+(reviewData.three_variant_cells||0)+' 格达到三稿数量目标。此数量不代表题型已经收全，听力、地方具体模式及配套仍在补核。'+(reviewData.unfilled_specific_modes?'另有 '+reviewData.unfilled_specific_modes+' 个已观察的具体模式尚未达到三套完整原创，矩阵已列待补。':'')+'需AI整体语义评分的主观题仍暂停。'+(reviewData.paused_concrete_groups?'另有 '+reviewData.paused_concrete_groups+' 个历史完整填空组暂缓，新编组不替其解除暂停。':''):'当前 '+(reviewData.source_form_representative_cells||reviewData.preview_cells)+' 个年级/题型格有样本完整形式参照；另 '+(reviewData.prototype_source_mode_pending_cells||0)+' 个设计原型待核源图，其余证据状态逐项列明。';
if(reviewData.pending_specific_modes?.length&&el('pending-modes')){
 const pending=reviewData.pending_specific_modes.filter(m=>m.remainingWholeOriginals);
 el('pending-modes').hidden=!pending.length;
 el('pending-modes-body').innerHTML='<p>以下已观察到题组结构或读者层骨架；完整题面、必要媒体及配套的缺口逐项列明。待补稿数只计同一具体来源模式的完整原创，不用同题型另一配置抵数。</p><ul>'+pending.map(m=>'<li><strong>'+escapeText(labels[m.grade]+' · '+m.title)+'</strong>：已有'+m.currentGroupIds.length+' / 目标'+m.target_whole_originals+'完整组。'+escapeText(m.source_gap)+'</li>').join('')+'</ul>';
}
const families=[...new Set(reviewData.cells.map(c=>c.family))];
if(el('coverage-audit')){
 const audit=reviewData.coverage_audit;
 el('coverage-audit').hidden=!audit;
 if(audit)el('coverage-audit-body').innerHTML='<p>'+escapeText(audit.scope_notice)+'</p><ul>'+audit.issues.map(i=>'<li>'+escapeText(i.levels.map(l=>labels[l]||l).join('、')+'：'+i.label+' — '+i.state_label+'。'+i.detail)+'</li>').join('')+'</ul>';
}
el('matrix-body').innerHTML=families.map(f=>'<tr><th scope="row">'+escapeText(reviewData.cells.find(c=>c.family===f).label)+'</th>'+reviewData.grades.map(grade=>{const c=reviewData.cells.find(c=>c.grade===grade&&c.family===f);return '<td><button type="button" data-grade="'+grade+'" data-family="'+f+'" class="'+(c.state==='author_prototype_source_mode_pending'?'pending':c.groupId?'ready':!c.observed?'unknown':'pending')+'">'+titleState(c)+'</button></td>';}).join('')+'</tr>').join('');
el('matrix-body').onclick=e=>{const b=e.target.closest('button[data-grade]');if(b)select(reviewData.grades.find(g=>String(g)===b.dataset.grade),b.dataset.family);};
el('show-unknown').onchange=()=>{if(!el('show-unknown').checked&&!reviewData.cells.find(c=>c.grade===activeGrade&&c.family===activeFamily).observed)activeFamily=reviewData.cells.find(c=>c.grade===activeGrade&&c.groupId)?.family||activeFamily;render();};render();
