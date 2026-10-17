const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'quality_review_interactions.js'),'utf8');
const start=source.indexOf('function closedSelectionComparison(');
const end=source.indexOf('\nfunction clearSelectionComparison(',start);
const context=vm.createContext({});
vm.runInContext(source.slice(start,end)+'\nthis.compare=answerComparison;',context);
const compare=context.compare;
const fill=(number,answers,extra={})=>({number,options:[],acceptedAnswers:answers,fillMarking:{version:1,review:'author_context_checked',normalization:'latin_word_v1',unlisted:'review',rejectedAnswers:['ORGANISE'],...extra}});
let qs=[fill(1,['ORGANISATION','ORGANIZATION']),fill(2,['RECOGNISABLE','RECOGNIZABLE','RECOGNISED','RECOGNIZED'])];
let r=compare(qs,{'1.1':' organization ','2.1':'recognised'});
assert.equal(r.matched,2);assert.equal(r.review,0);assert.equal(r.different,0);
for(const form of qs[1].acceptedAnswers)assert.equal(compare(qs,{'2.1':form}).matched,1);
r=compare(qs,{'1.1':'ORGANISE','2.1':'UNLISTED'});
assert.equal(r.different,1);assert.equal(r.review,1);assert.equal(r.matched,0);
r=compare(qs,{'1.1':'   '});assert.equal(r.unanswered,2);
// No word splitting, root stripping, fuzzy correction, or punctuation erasure.
for(const wrong of ['ORGANISATION!','ORGANISATION ORGANIZATION','ＯＲＧＡＮＩＳＡＴＩＯＮ']){
 assert.equal(compare(qs,{'1.1':wrong}).different,1);
}
const numeric=[fill(1,['2'],{normalization:'ascii_integer_v1',unlisted:'different',rejectedAnswers:[]})];
assert.equal(compare(numeric,{'1.1':' ００２ '}).matched,1);
for(const wrong of ['2.0','two','-2','2/1','2 0','3'])assert.equal(compare(numeric,{'1.1':wrong}).different,1);
// knownForms alone is not admission. Full-group refusal must not partially grade.
assert.equal(compare([...qs,{number:3,options:[],knownForms:['rest']}],{'1.1':'organization'}).available,false);
assert.equal(compare([fill(1,['ORGANISATION','organisation'])]).available,false);
assert.equal(compare([fill(1,['ORGANISATION'],{rejectedAnswers:['ORGANISATION']})]).available,false);
assert.equal(compare([fill(1,['ORGANISATION'],{unlisted:'different'})]).available,false);
assert.equal(compare([fill(1,['ORGANISATION'],{normalization:'fuzzy'})]).available,false);
assert.equal(compare([fill(1,['ORGANISATION'],{review:'unreviewed'})]).available,false);
assert.equal(compare([qs[0],qs[0]]).available,false);
assert.equal(compare(qs,{'1.1':123}).available,false);
const mixed=[qs[0],{number:2,options:[['A','one'],['B','two']],answer:'B'}];
r=compare(mixed,{'1.1':'organization',2:'B'});assert.equal(r.matched,2);
assert.equal(compare(mixed,{2:'Z'}).available,false);
assert.equal(compare([]).available,false);
// Integrate with every actual new complete group; exercise all alternate forms.
const page=fs.readFileSync(path.join(__dirname,'../../../build/english-benchmark-quality-review/index.html'),'utf8');
const data=JSON.parse(page.match(/<script id="quality-data" type="application\/json">(.*?)<\/script>/s)[1]);
let groups=0,responses=0,alternatives=0;
for(const g of Object.values(data.groups).filter(g=>g.questions.some(q=>q.acceptedAnswers))){
 const saved=Object.fromEntries(g.questions.map(q=>[q.number+'.1',q.acceptedAnswers[0]]));
 assert.equal(compare(g.questions,saved).matched,g.questions.length);
 for(const q of g.questions){
  for(const form of q.acceptedAnswers){assert.equal(compare(g.questions,{...saved,[q.number+'.1']:form.toLowerCase()}).matched,g.questions.length);alternatives++;}
  for(const wrong of q.fillMarking.rejectedAnswers)assert.equal(compare(g.questions,{...saved,[q.number+'.1']:wrong}).different,1);
 }
 groups++;responses+=g.questions.length;
}
assert.equal(groups,7);assert.equal(responses,48);
console.log(JSON.stringify({passed:true,cases:25,actual_fill_groups:groups,actual_fill_positions:responses,accepted_forms_checked:alternatives,no_three_answer_cap:true,unknown_not_marked_wrong:true,full_group_contract:true,local_not_production:true}));
