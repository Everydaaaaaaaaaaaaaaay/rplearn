const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'quality_review_interactions.js'),'utf8');
const start=source.indexOf('function closedSelectionComparison('),end=source.indexOf('\nfunction clearSelectionComparison(',start),ctx=vm.createContext({});
vm.runInContext(source.slice(start,end)+'\nthis.compare=answerComparison;',ctx);
const fill=(number,acceptedAnswers,rejectedAnswers=[])=>({number,options:[],acceptedAnswers,fillMarking:{version:1,review:'author_context_checked',normalization:'source_excerpt_v1',sourceBound:true,unknownSyntax:'review',hyphenatedWordCount:'one',maxWords:3,unlisted:'review',rejectedAnswers}});
const q=fill(1,['two to five','2-5'],['two to six','2-6']);let cases=0;
function state(question,text,expected){const result=ctx.compare([question],{[question.number+'.1']:text});assert.equal(result.available,true);assert.equal(result.rows[0].state,expected,text);cases++;}
for(const v of ['two to five',' TWO   TO FIVE ','2-5','２–５','2−5','2‑5'])state(q,v,'match');
for(const v of ['two to six','2-6','two up to five'])state(q,v,'different');
for(const v of ['2 to 5','two-five','2 - 5','2—5','2/5','2-5!','approximately 2-5'])state(q,v,'review');
state(q,' ','unanswered');
const spelling=fill(1,['South African tunneling','South African tunnelling']);
for(const v of spelling.acceptedAnswers)state(spelling,v,'match');
state(spelling,'South African tunnelling species','different');
const hyphen=fill(1,['sub-tropical']);hyphen.fillMarking.maxWords=1;
state(hyphen,'sub‑tropical','match');state(hyphen,'sub tropical','different');state(hyphen,'semi-tropical','review');
const four=fill(1,['organise','organize','organised','organized']);
for(const v of four.acceptedAnswers)state(four,v,'match');
for(const key of ['sourceBound','unknownSyntax','hyphenatedWordCount','maxWords']){const bad=structuredClone(q);delete bad.fillMarking[key];assert.equal(ctx.compare([bad]).available,false);cases++;}
const bad=structuredClone(q);bad.acceptedAnswers=['2-5','２–５'];assert.equal(ctx.compare([bad]).available,false);cases++;
const old=structuredClone(q);old.fillMarking.normalization='english_phrase_v1';assert.equal(ctx.compare([old]).available,false);cases++;
console.log(JSON.stringify({passed:true,cases,scope:'bounded_source_excerpt_only',unknownSyntax:'review',no_three_answer_cap:true,old_word_protocol_not_weakened:true}));
