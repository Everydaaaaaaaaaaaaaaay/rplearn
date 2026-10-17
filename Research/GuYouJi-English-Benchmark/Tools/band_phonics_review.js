/* Closed letter responses only; no semantic judgement or general fill inference. */
function compareLetter(value, expected) {
  const normalized=String(value).normalize('NFKC').trim().toLowerCase();
  return !normalized?'unanswered':!['p','b'].includes(normalized)?'invalid':normalized===expected?'match':'different';
}
if(typeof module!=='undefined')module.exports={compareLetter};
if(typeof document!=='undefined'){
  const data=JSON.parse(document.getElementById('band-data').textContent);
  const el=id=>document.getElementById(id),drafts={};let selected=data.groups[0].id;
  const escape=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const group=()=>data.groups.find(g=>g.id===selected);
  function save(){drafts[selected]=Object.fromEntries([...document.querySelectorAll('#lists input')].map(i=>[i.name,i.value]));}
  function render(){
    el('audio').pause();const d=group();
    el('title').textContent=d.title;el('instruction').textContent=d.instruction;el('audio').src=d.audio_url;el('teacher').hidden=true;el('result').textContent='';
    el('audio').onerror=()=>{el('result').textContent='音频载入失败，请勿只凭文字作听力核对。';el('compare').disabled=true;};
    el('audio').onloadeddata=()=>{el('compare').disabled=false;};el('compare').disabled=true;
    el('lists').innerHTML='<thead><tr>'+d.lists.map(l=>'<th scope="col">'+escape(l.name)+'’s list</th>').join('')+'</tr></thead><tbody>'+[0,1,2,3,4].map(row=>'<tr>'+d.lists.map(l=>{
      const i=l.items[row];return '<td>'+(i.example?'<span class="example">已解示例：'+escape(i.prefix)+' <b>'+escape(i.letter)+'</b>'+escape(i.full_word.slice(1))+'</span>':'<label><small>'+i.number+'.</small> '+escape(i.prefix)+' <input type="text" name="'+i.number+'" aria-label="'+escape(l.name+'：'+i.prefix+' '+i.stub)+'" value="'+escape(drafts[d.id]?.[i.number]||'')+'" autocomplete="off" autocapitalize="off" spellcheck="false">'+escape(i.full_word.slice(1))+'</label>')+'</td>';
    }).join('')+'</tr>').join('')+'</tbody>';
    el('lists').oninput=save;
    el('teacher-body').innerHTML=d.questions.map(q=>'<p><b>'+escape(q.number+'. '+q.stem+' → '+q.acceptedAnswers[0])+'</b><br>'+escape(q.rationale)+'</p>').join('')+'<h3>完整原创脚本</h3>'+d.turns.map(t=>'<p>'+escape(d.lists.find(l=>l.speaker===t.speaker).name+': '+t.text)+'</p>').join('');
    el('rate').textContent=d.local_rate_notice+' 本音轨实测 '+d.measured_rate.toFixed(1)+' 英文词/分钟（不含额外停顿）。';
  }
  el('variants').innerHTML=data.groups.map(g=>'<option value="'+escape(g.id)+'">'+escape(g.title)+'</option>').join('');
  el('variants').onchange=()=>{save();selected=el('variants').value;render();};
  el('compare').onclick=()=>{
    save();const d=group(),rows=d.questions.map(q=>({number:q.number,state:compareLetter(drafts[selected]?.[q.number]||'',q.acceptedAnswers[0])}));
    const labels={match:'与参考一致',different:'与录音不同',invalid:'不在 p/b 候选内',unanswered:'未答'};
    el('result').textContent=Object.entries(labels).map(([state,label])=>rows.filter(r=>r.state===state).length+' '+label).join('；')+'。'+rows.map(r=>r.number+'：'+labels[r.state]).join('，');
  };
  el('reveal').onclick=()=>{el('teacher').hidden=!el('teacher').hidden;};
  el('reset').onclick=()=>{drafts[selected]={};render();};
  render();
}
