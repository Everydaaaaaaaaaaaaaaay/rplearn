const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'../../..'),base=path.join(root,'Research/GuYouJi-English-Benchmark');
const source=fs.readFileSync(path.join(__dirname,'quality_review_interactions.js'),'utf8');
const ctx=vm.createContext({});vm.runInContext(source.slice(source.indexOf('function closedSelectionComparison('),source.indexOf('\nfunction clearSelectionComparison('))+'\nthis.compare=answerComparison;',ctx);
const metas=JSON.parse(fs.readFileSync(path.join(root,'build/english-benchmark-authority-20261017/wordorder646-metadata-v0.1.json')));
let accepted=0,controls=0;const reports=[];
for(const meta of metas){
 const audit=JSON.parse(fs.readFileSync(path.join(base,meta.author_check.path))),qs=audit.review_response_tasks,saved=Object.fromEntries(qs.map(q=>[q.number+'.1',q.acceptedAnswers[0]]));
 assert.equal(ctx.compare(qs,saved).matched,5);
 for(const q of qs)for(const sentence of q.acceptedAnswers){assert.equal(ctx.compare(qs,{...saved,[q.number+'.1']:sentence}).matched,5);accepted++;}
 const status=(number,text,state)=>{const result=ctx.compare(qs,{...saved,[number+'.1']:text});assert.equal(result.rows[number-1].state,state,JSON.stringify({number,text,result}));controls++;};
 status(1,qs[0].acceptedAnswers[0].replace(' I ',' '),'different'); // repeated I is a real pool occurrence
 status(1,qs[0].acceptedAnswers[0].replace(' I ',' I I '),'different');
 status(1,qs[0].acceptedAnswers[0].replace(' I ',' i '),'different');
 status(1,qs[0].acceptedAnswers[0].toLowerCase(),'different');
 status(1,qs[0].acceptedAnswers[0].replace(/\.$/,''),'different');
 status(1,qs[0].acceptedAnswers[0].replace('I always','I never'),'different');
 status(1,'','unanswered');
 status(1,qs[0].acceptedAnswers[0].replace(/ /g,'  '),'match');
 status(1,qs[0].acceptedAnswers[0].replace(', ', ' ,'),'match');
 status(1,qs[0].acceptedAnswers[0].replace(/\.$/,'!'),'different');
 status(1,qs[0].acceptedAnswers[0].replace(/\.$/,';'),'review');
 status(1,qs[0].acceptedAnswers[0]+' 😊','review');
 status(3,qs[2].acceptedAnswers[0].replace(' are ',' is '),'different');
 status(5,qs[4].acceptedAnswers[0].replace(/\?$/,'.'),'different');
 const middle=qs[3].acceptedAnswers[0].replace(/^I think (\w)(.*)\.$/,(_,a,b)=>a.toUpperCase()+b.replace(' are ', ', I think, are ')+'.');
 status(4,middle,'review'); // real unlisted parenthetic arrangement is not wrong
 if(meta.id.endsWith('crossing'))status(2,qs[1].acceptedAnswers[0].replace("o'clock",'o’clock'),'match');
 const refuse=change=>{const q=structuredClone(qs);change(q);assert.equal(ctx.compare(q,saved).available,false);controls++;};
 refuse(q=>q.pop());refuse(q=>q[0].wordPool.pop());refuse(q=>q[0].wordPool.push('extra'));
 refuse(q=>q[0].wordOrder.id='other');refuse(q=>q[0].wordOrder.positions.pop());
 refuse(q=>q[0].fillMarking.caseRule='ignore');refuse(q=>q[0].fillMarking.useAllTokens='set');
 refuse(q=>q[0].fillMarking.unlisted='different');refuse(q=>q[0].fillMarking.maxWords=13);
 refuse(q=>q[0].acceptedAnswers.push(q[0].acceptedAnswers[0]));
 refuse(q=>q[0].acceptedAnswers.push(q[0].acceptedAnswers[0].toLowerCase()));
 refuse(q=>q[0].acceptedAnswers.push(q[0].acceptedAnswers[0].replace(' I ',' ')));
 refuse(q=>q[0].fillMarking.rejectedAnswers=[q[0].acceptedAnswers[0]]);
 reports.push({id:meta.id,known_forms:qs.map(q=>q.acceptedAnswers.length),independent_pool_cartesian:audit.full_fill_variant_combinations});
}
console.log(JSON.stringify({passed:true,complete_groups:3,response_positions:15,accepted_sentences_in_whole_groups:accepted,controls,report:reports,unknown_order_review:true,case_punctuation_and_multiset:true,local_not_production:true}));
