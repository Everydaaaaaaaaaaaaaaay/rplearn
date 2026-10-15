/* Synthetic interaction guard controls; actual browser rendering is checked separately. */
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const [pagePath,reportPath]=process.argv.slice(2);
const page=fs.readFileSync(pagePath,'utf8');
const data=page.match(/<script id="showcase-data" type="application\/json">([\s\S]*?)<\/script>/)[1];
const code=page.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
const cases=[];
function setup(imageStates,visual=true){
 const nodes=new Map();
 const element=()=>({children:[],hidden:false,textContent:'',_html:'',set innerHTML(v){this._html=v;this.children=[];},get innerHTML(){return this._html;},append(v){this.children.push(v);},after(){},setAttribute(){},addEventListener(){}});
 for(const key of ['showcase-data','grades','types','groups','grade-title','instruction','passage','quiz','result','submit','reveal','reset','full-review','provenance'])nodes.set(key,element());
 nodes.get('showcase-data').textContent=data;
 const document={getElementById:id=>nodes.get(id)||null,createElement:()=>element(),querySelectorAll:selector=>selector==='#quiz img.option-image'?imageStates:[]};
 const context=vm.createContext({document});vm.runInContext(code,context);
 if(visual)vm.runInContext("active=items.findIndex(g=>g.id==='grade7-reading-corner-images-v0.1');render();",context);
 return {nodes,context};
}
const ready=()=>({complete:true,naturalWidth:300});
for(const [label,images] of [['none',[]],['only3',[ready(),ready(),ready()]],['loading',[ready(),ready(),ready(),{complete:false,naturalWidth:0}]],['broken',[ready(),ready(),ready(),{complete:true,naturalWidth:0}]]]){
 for(const action of ['submit','reveal']){
  const {nodes,context}=setup(images);nodes.get(action).onclick();
  assert.match(nodes.get('result').textContent,/四幅图片尚未完整显示/);
  assert.equal(vm.runInContext('states[active].submitted',context),false);
  cases.push({case:label+' images block '+action,passed:true,result:nodes.get('result').textContent});
 }
}
{
 const {nodes,context}=setup([ready(),ready(),ready(),ready()]);
 vm.runInContext("states[active].answers={1:'B',2:'D',3:'A'}",context);nodes.get('submit').onclick();
 assert.equal(vm.runInContext('states[active].submitted',context),true);assert.match(nodes.get('result').textContent,/答对 3 题/);
 cases.push({case:'all4ready permits complete3 response check',passed:true,result:nodes.get('result').textContent});
}
{
 const {nodes,context}=setup([ready(),ready(),ready(),ready()]);nodes.get('reveal').onclick();
 assert.equal(vm.runInContext('states[active].submitted',context),true);
 cases.push({case:'all4ready permits reference without fabricated attempts',passed:true,result:nodes.get('result').textContent});
}
{
 const {nodes,context}=setup([],false);nodes.get('reveal').onclick();
 assert.equal(vm.runInContext('states[active].submitted',context),true);
 cases.push({case:'original text group requires no images',passed:true,result:nodes.get('result').textContent});
}
const result={cases,controls:cases.length,positive:3,rejection:8,synthetic_JS_VM_not_browser:true,production_called:false};
fs.writeFileSync(reportPath,JSON.stringify(result,null,2)+'\n');process.stdout.write(JSON.stringify({controls:result.controls,positive:3,rejection:8})+'\n');
