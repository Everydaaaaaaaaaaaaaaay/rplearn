const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'quality_review_interactions.js'),'utf8');
const start=source.indexOf('function closedSelectionComparison('),end=source.indexOf('\nfunction clearSelectionComparison(',start),ctx=vm.createContext({});
vm.runInContext(source.slice(start,end)+'\nthis.compare=answerComparison;',ctx);
const q={number:1,options:[],acceptedAnswers:['spatial material atmospheric'],fillMarking:{version:1,review:'author_context_checked',normalization:'source_list_v1',sourceBound:true,unknownSyntax:'review',hyphenatedWordCount:'one',maxWords:3,unlisted:'review',rejectedAnswers:['spatial material temporal'],listSize:3,listOrder:'any',listMembersDistinct:true}};
let cases=0;
function state(question,text,expected){const result=ctx.compare([question],{'1.1':text});assert.equal(result.available,true);assert.equal(result.rows[0].state,expected,text);cases++;}
function permutations(xs){return xs.length?xs.flatMap((x,i)=>permutations(xs.filter((_,j)=>i!==j)).map(p=>[x,...p])):[[]];}
for(const p of permutations(['spatial','material','atmospheric']))for(const sep of [' ',', ', ' ,','\t'])state(q,p.join(sep),'match');
for(const v of ['spatial material','spatial spatial atmospheric','spatial material atmospheric extra','spatial, material and atmospheric','spatial material temporal'])state(q,v,'different');
for(const v of ['spatial; material; atmospheric','spatial,, material, atmospheric',',spatial material atmospheric','spatial material atmospheric,','spatial material atmospheric.','spatial material unknown'])state(q,v,'review');
state(q,'   ','unanswered');
for(const field of ['sourceBound','listSize','listOrder','listMembersDistinct','maxWords','unknownSyntax']){const bad=structuredClone(q);delete bad.fillMarking[field];assert.equal(ctx.compare([bad]).available,false,field);cases++;}
for(const answers of [['spatial material atmospheric','material spatial atmospheric'],['spatial spatial atmospheric'],['spatial material']]){const bad=structuredClone(q);bad.acceptedAnswers=answers;assert.equal(ctx.compare([bad]).available,false);cases++;}
const old=structuredClone(q);old.fillMarking.normalization='source_excerpt_v1';state(old,'spatial, material, atmospheric','review');
console.log(JSON.stringify({passed:true,cases,unordered_three_members_one_response:true,old_excerpt_punctuation_unchanged:true,unknown_forms_review:true}));
