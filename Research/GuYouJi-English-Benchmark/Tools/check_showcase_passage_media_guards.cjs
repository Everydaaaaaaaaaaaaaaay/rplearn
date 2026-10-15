/* Synthetic DOM controls for required passage graphs; not browser rendering. */
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const [pagePath,reportPath]=process.argv.slice(2),page=fs.readFileSync(pagePath,'utf8');
const data=page.match(/<script id="showcase-data" type="application\/json">([\s\S]*?)<\/script>/)[1];
const code=page.match(/<script>\s*([\s\S]*?)<\/script>/)[1],items=JSON.parse(data),cases=[];
function setup(id,graphStates){
 const nodes=new Map();
 const element=()=>({children:[],hidden:false,textContent:'',_html:'',set innerHTML(v){this._html=v;this.children=[];},get innerHTML(){return this._html;},append(v){this.children.push(v);},after(){},setAttribute(){},addEventListener(){}});
 for(const key of ['showcase-data','grades','types','groups','grade-title','instruction','passage','quiz','result','submit','reveal','reset','full-review','provenance'])nodes.set(key,element());
 nodes.get('showcase-data').textContent=data;
 const document={getElementById:id=>nodes.get(id)||null,createElement:()=>element(),querySelectorAll:selector=>selector==='#passage img.passage-image'?graphStates:[]};
 const context=vm.createContext({document});vm.runInContext(code,context);
 vm.runInContext('active=items.findIndex(g=>g.id==='+JSON.stringify(id)+');render();',context);
 return {nodes,context};
}
function image(ref,overrides={}){
 const attrs={src:ref.src,alt:ref.alt,...overrides.attrs};
 return {complete:true,naturalWidth:ref.width,...overrides,getAttribute:key=>attrs[key]};
}
for(const id of ['grade12-library-electricity','grade8-library-survey-reading']){
 const g=items.find(g=>g.id===id),ref=g.requiredPassageImages[0];
 const invalid=[['absent',[]],['loading',[image(ref,{complete:false,naturalWidth:0})]],['broken',[image(ref,{naturalWidth:0})]],['extra',[image(ref),image(ref)]],['wrongSVG',[image(ref,{attrs:{src:'data:image/svg+xml;base64,wrong'}})]],['wrongAlt',[image(ref,{attrs:{alt:'a missing description'}})]]];
 for(const [label,images] of invalid){
  for(const action of ['submit','reveal']){
   const {nodes,context}=setup(id,images);nodes.get(action).onclick();
   assert.match(nodes.get('result').textContent,/图表尚未完整显示/);
   assert.equal(vm.runInContext('states[active].submitted',context),false);
   cases.push({case:id+' '+label+' blocks '+action,passed:true,result:nodes.get('result').textContent});
  }
 }
 for(const action of ['submit','reveal']){
  const {nodes,context}=setup(id,[image(ref)]);
  if(action==='submit')vm.runInContext('states[active].answers='+JSON.stringify(Object.fromEntries(g.questions.map(q=>[q.number,q.answer]))),context);
  nodes.get(action).onclick();assert.equal(vm.runInContext('states[active].submitted',context),true);
  assert.match(nodes.get('result').textContent,action==='submit'?/答对 3 题/:/已作答 0\/3/);
  cases.push({case:id+' correct graph permits '+action,passed:true,result:nodes.get('result').textContent});
 }
}
{
 const {nodes,context}=setup('grade9-repair-table-reading',[]);nodes.get('reveal').onclick();
 assert.equal(vm.runInContext('states[active].submitted',context),true);
 cases.push({case:'HTML table requires no image',passed:true});
}
const result={cases,controls:cases.length,positive:5,rejection:24,synthetic_JS_VM_not_browser:true,production_called:false};
fs.writeFileSync(reportPath,JSON.stringify(result,null,2)+'\n');process.stdout.write(JSON.stringify({controls:result.controls,positive:5,rejection:24})+'\n');
