const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const js = fs.readFileSync(path.join(__dirname, 'quality_review_interactions.js'), 'utf8');
const context = vm.createContext({});
vm.runInContext(js.slice(js.indexOf('function closedSelectionComparison('), js.indexOf('\nfunction clearSelectionComparison(')) + '\nthis.compare=answerComparison;', context);
const compare = context.compare;
const fixture = {number:1, options:[], givenCandidates:['learned','learnt'], acceptedAnswers:['learned','learnt'], fillMarking:{version:1, review:'author_context_checked', normalization:'english_phrase_v1', maxWords:null, unlisted:'review', unknownSyntax:'review', closedCandidates:true, rejectedAnswers:[]}};
for (const value of ['learned','learnt','  LEARNT  ']) assert.equal(compare([fixture], {'1.1':value}).matched, 1);
assert.equal(compare([fixture], {'1.1':'learning'}).different, 1);
assert.equal(compare([fixture], {'1.1':'learned / learnt'}).review, 1);
assert.equal(compare([fixture], {'1.1':''}).unanswered, 1);
let rejectedContracts = 0;
const reject = change => { const q=structuredClone(fixture); change(q); assert.equal(compare([q]).available, false); rejectedContracts++; };
reject(q => delete q.fillMarking.closedCandidates);
reject(q => delete q.givenCandidates);
for (const value of [false,null,'true']) reject(q => q.fillMarking.closedCandidates=value);
reject(q => q.givenCandidates=[]);
reject(q => q.givenCandidates=['learned']);
reject(q => q.givenCandidates=['learned','LEARNED']);
reject(q => q.givenCandidates=['learned',null]);
reject(q => q.givenCandidates=['learned','learnt!']);
reject(q => q.givenCandidates.push('learning'));
reject(q => q.acceptedAnswers=['learning']);
reject(q => q.fillMarking.rejectedAnswers=['learnt']);
reject(q => {q.acceptedAnswers=['learned'];q.fillMarking.rejectedAnswers=['learnt','learnt'];});
reject(q => q.fillMarking.normalization='latin_word_v1');
// The runtime has no arbitrary two/three-answer cap; the source compiler binds this batch's pair size.
const four=structuredClone(fixture);four.givenCandidates=four.acceptedAnswers=['one','two','three','four'];
for (const value of four.acceptedAnswers) assert.equal(compare([four], {'1.1':value}).matched, 1);
// Open fills remain nonexclusive when a printed closed pool is absent.
const open=structuredClone(fixture);delete open.givenCandidates;delete open.fillMarking.closedCandidates;
assert.equal(compare([open], {'1.1':'learning'}).review, 1);
let groups=0, responses=0, combinations=0, correctInputs=0, rejectedCandidates=0;
const repo=path.resolve(__dirname,'../../..');
const metadata=JSON.parse(fs.readFileSync(path.join(repo,'build/english-benchmark-authority-20261017/p6pair636-metadata-v0.1.json')));
for (const meta of metadata) {
 const a=JSON.parse(fs.readFileSync(path.join(repo,'Research/GuYouJi-English-Benchmark',meta.author_check.path)));
 const qs=a.review_response_tasks; assert.equal(qs.length,10);groups++;responses+=qs.length;
 let savedSets=[{}];
 for (const q of qs) savedSets=savedSets.flatMap(saved=>q.acceptedAnswers.map(value=>({...saved,[q.number+'.1']:value})));
 assert.equal(savedSets.length,a.full_fill_variant_combinations);
 for (const saved of savedSets) {const result=compare(qs,saved);assert.equal(result.matched,10);assert.equal(result.review,0);combinations++;correctInputs+=10;}
 for (const q of qs) {
  assert.equal(compare(qs,{[q.number+'.1']:'unprinted'}).different,1);
  for (const value of q.fillMarking.rejectedAnswers) {assert.equal(compare(qs,{[q.number+'.1']:value}).different,1);rejectedCandidates++;}
 }
 const phrase=qs[4];assert.equal(compare(qs,{[phrase.number+'.1']:'  '+phrase.acceptedAnswers[0].toUpperCase().replace(' ','   ')+'  '}).matched,1);
}
console.log(JSON.stringify({passed:true,rejectedContracts,groups,responses,fullAcceptedCombinations:combinations,correctInputs,rejectedCandidates,noAnswerCountCap:true,openFillUnknownStillReview:true,closedPoolOutsideDifferent:true,localNotProduction:true}));
