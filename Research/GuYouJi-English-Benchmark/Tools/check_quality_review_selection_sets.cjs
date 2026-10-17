const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'quality_review_interactions.js'),'utf8');const start=source.indexOf('function closedSelectionComparison('),end=source.indexOf('\nfunction clearSelectionComparison(',start),ctx=vm.createContext({});vm.runInContext(source.slice(start,end)+'\nthis.compare=answerComparison;',ctx);
const make=(id,positions,correct,labels)=>positions.map((number,i)=>({number,options:labels.split('').map(k=>[k,'Option '+k]),answer:correct[i],selectionSet:{version:1,id,positions,correct,order:'either',distinct:true,localMatchingRule:'distinct_correct_options_once'}}));
const questions=[...make('first',[1,2],['B','G'],'ABCDEFG'),...make('second',[3,4],['C','E'],'ABCDEF')];let cases=0;
for(const pair of [['B','G'],['G','B']])for(const pair2 of [['C','E'],['E','C']]){assert.equal(ctx.compare(questions,{1:pair[0],2:pair[1],3:pair2[0],4:pair2[1]}).matched,4);cases++;}
for(const correct of ['B','G']){const r=ctx.compare(questions,{1:correct,2:correct,3:'C',4:'E'});assert.equal(r.matched,3);assert.equal(r.different,1);assert.equal(r.selectionConflicts.length,1);cases++;}
for(const data of [{1:'B',2:'A',3:'C',4:'E'},{1:'A',2:'G',3:'E',4:'C'}]){assert.equal(ctx.compare(questions,data).matched,3);cases++;}
assert.equal(ctx.compare(questions,{1:'B'}).matched,1);assert.equal(ctx.compare(questions,{1:'B'}).unanswered,3);cases+=2;
assert.equal(ctx.compare(questions,{1:'Z'}).available,false);cases++;
for(const mutation of [q=>q.pop(),q=>delete q[0].selectionSet,q=>q[1].selectionSet.correct.reverse(),q=>q[0].selectionSet.order='fixed',q=>q[1].options.pop(),q=>q.reverse(),q=>q[0].selectionSet.positions=[1,1],q=>q[1].selectionSet.id='other',q=>q[1].answer='B']){const q=structuredClone(questions);mutation(q);assert.equal(ctx.compare(q).available,false);cases++;}
// A letter may occur in both independent prompts without a global reuse ban.
const independent=[...make('one',[1,2],['A','B'],'ABC'),...make('two',[3,4],['A','B'],'ABC')];assert.equal(ctx.compare(independent,{1:'A',2:'B',3:'B',4:'A'}).matched,4);cases++;
console.log(JSON.stringify({passed:true,cases,pair_order_independent:true,duplicates_not_double_matched:true,no_cross_prompt_once_rule:true,source_partial_credit_not_inferred:true}));
