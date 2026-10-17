const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'quality_review_interactions.js'),'utf8');
const start=source.indexOf('function closedSelectionComparison('),end=source.indexOf('\nfunction clearSelectionComparison(',start);
const ctx=vm.createContext({});
vm.runInContext(source.slice(start,end)+'\nthis.compare=answerComparison;this.normalize=normalizeFill;',ctx);
const page=fs.readFileSync(path.join(__dirname,'../../../build/english-benchmark-quality-review/index.html'),'utf8');
const data=JSON.parse(page.match(/<script id="quality-data" type="application\/json">(.*?)<\/script>/s)[1]);
const numeric=data.groups['primary1-eight-number-words'],phonetic=data.groups['grade7-phonetic-word-completion'];
const saved=g=>Object.fromEntries(g.questions.map(q=>[q.number+'.1',q.acceptedAnswers[0]]));
assert.equal(numeric.questions.length,8);assert.equal(phonetic.questions.length,4);
for(const g of [numeric,phonetic])assert.equal(ctx.compare(g.questions,saved(g)).matched,g.questions.length);
let count=12;
for(const value of ['7',' 007 ','００７','٠٠٧','۰۰۷','००७','𝟟','⑦','⁷','\u00857\u0085','\u001c7\u001f']){
 const r=ctx.compare(numeric.questions,{...saved(numeric),'1.1':value});assert.equal(r.matched,8);assert.equal(r.review,0);count++;
}
for(const value of ['7.0','7/1','+7','seven','7!','-7','7 0','\ufeff7']){
 const r=ctx.compare(numeric.questions,{...saved(numeric),'1.1':value});assert.equal(r.matched,7);assert.equal(r.review,1);assert.equal(r.different,0);count++;
}
for(const value of ['8','0008','８','٨']){
 const r=ctx.compare(numeric.questions,{...saved(numeric),'1.1':value});assert.equal(r.different,1);assert.equal(r.review,0);count++;
}
assert.equal(ctx.compare(numeric.questions,{}).unanswered,8);count+=8;
for(const [n,form] of [[1,' REST '],[2,'Dish'],[3,'FEED'],[4,'SmElL']]){
 assert.equal(ctx.compare(phonetic.questions,{...saved(phonetic),[n+'.1']:form}).matched,4);count++;
}
for(const [n,form] of [[1,'wrest'],[2,'plate'],[3,'fed'],[4,'smile'],[1,'rest!'],[2,'ｄｉｓｈ']]){
 const r=ctx.compare(phonetic.questions,{...saved(phonetic),[n+'.1']:form});assert.equal(r.matched,3);assert.equal(r.review,1);assert.equal(r.different,0);count++;
}
assert.equal(ctx.compare(phonetic.questions,{}).unanswered,4);count+=4;
// A specialized legacy protocol must not widen the other number-word groups.
assert.equal(ctx.normalize('٧','ascii_integer_v1'),null);count++;
const malformed=JSON.parse(JSON.stringify(numeric.questions));malformed[0].fillMarking.normalization='unsupported_v1';assert.equal(ctx.compare(malformed,saved(numeric)).available,false);count++;
const lexical=JSON.parse(JSON.stringify(phonetic.questions));lexical[0].fillMarking.unlisted='different';assert.equal(ctx.compare(lexical,saved(phonetic)).available,false);count++;
let oracle=0;
if(process.argv[2])for(const row of JSON.parse(fs.readFileSync(process.argv[2],'utf8'))){assert.equal(ctx.normalize(row.input,'unicode_decimal_integer_v1'),row.expected);oracle++;}
console.log(JSON.stringify({passed:true,focused_cases:count,decimal_oracle_cases:oracle,whole_existing_groups:2,response_positions:12,student_inputs_known_answers_unchanged:true,unknown_syntax_and_lexical_forms_review:true,no_three_answer_cap_introduced:true,other_ascii_protocol_unchanged:true,local_not_production:true}));
