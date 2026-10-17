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
const phrase={number:1,options:[],acceptedAnswers:['Established','Having been established'],fillMarking:{version:1,review:'author_context_checked',normalization:'english_phrase_v1',maxWords:null,unlisted:'review',rejectedAnswers:['Establishing']}};
assert.equal(compare([phrase],{'1.1':' having   been established '}).matched,1);
assert.equal(compare([phrase],{'1.1':'having been being established'}).review,1);
assert.equal(compare([phrase],{'1.1':'Establishing'}).different,1);
const oneWord={number:1,options:[],acceptedAnswers:['who','that'],fillMarking:{...phrase.fillMarking,maxWords:1,rejectedAnswers:['whom']}};
assert.equal(compare([oneWord],{'1.1':'who was'}).different,1);
assert.equal(compare([{...phrase,fillMarking:{...phrase.fillMarking,maxWords:1}}]).available,false);
assert.equal(compare([{...phrase,fillMarking:{...phrase.fillMarking,maxWords:undefined}}]).available,false);
// A source's explicit two-word slot is different from an ordinary one-word
// ungiven slot. Unlisted contractions/hyphenation cannot settle word counting.
const exactTwo={number:1,options:[],acceptedAnswers:['rather than','instead of'],fillMarking:{version:1,review:'author_context_checked',normalization:'english_phrase_v1',minWords:2,maxWords:2,wordCountAmbiguity:'review',unlisted:'review',rejectedAnswers:['because of']}};
assert.equal(compare([exactTwo],{'1.1':' INSTEAD   OF '}).matched,1);
assert.equal(compare([exactTwo],{'1.1':'rather than'}).matched,1);
assert.equal(compare([exactTwo],{'1.1':'instead'}).different,1);
assert.equal(compare([exactTwo],{'1.1':'in place of'}).different,1);
assert.equal(compare([exactTwo],{'1.1':'as against'}).review,1);
assert.equal(compare([exactTwo],{'1.1':'rather-than'}).review,1);
assert.equal(compare([exactTwo],{'1.1':"don't"}).review,1);
assert.equal(compare([exactTwo],{'1.1':'because of'}).different,1);
assert.equal(compare([exactTwo],{'1.1':' '}).unanswered,1);
assert.equal(compare([{...exactTwo,fillMarking:{...exactTwo.fillMarking,minWords:3}}]).available,false);
assert.equal(compare([{...exactTwo,fillMarking:{...exactTwo.fillMarking,minWords:0}}]).available,false);
// Source-bound transformations retain the unchanged keyword as a whole word.
const kwt={number:1,options:[],acceptedAnswers:['did not dawn on me'],fillMarking:{...exactTwo.fillMarking,minWords:3,maxWords:6,requiredWord:'DAWN',rejectedAnswers:['did not dawn to me']}};
assert.equal(compare([kwt],{'1.1':' DID  NOT DAWN ON ME '}).matched,1);
assert.equal(compare([kwt],{'1.1':'never dawned on me'}).different,1);
assert.equal(compare([kwt],{'1.1':'never dawn on me'}).review,1);
assert.equal(compare([kwt],{'1.1':'dawn on'}).different,1);
assert.equal(compare([kwt],{'1.1':'it did not dawn on me then'}).different,1);
assert.equal(compare([kwt],{'1.1':"didn't dawn on me"}).review,1);
assert.equal(compare([kwt],{'1.1':'did not dawn to me'}).different,1);
assert.equal(compare([kwt],{'1.1':'did not dawner on me'}).different,1);
assert.equal(compare([{...kwt,fillMarking:{...kwt.fillMarking,requiredWord:'DAWNED'}}]).available,false);
assert.equal(compare([{...kwt,fillMarking:{...kwt.fillMarking,requiredWord:'DAWN ON'}}]).available,false);
assert.equal(compare([{...kwt,fillMarking:{...kwt.fillMarking,requiredWord:123}}]).available,false);
const bankHelp={number:1,options:[],acceptedAnswers:['to help','to be helping'],bankEntry:'help',bankReuse:'once',fillMarking:{version:1,review:'author_context_checked',normalization:'english_phrase_v1',maxWords:null,unlisted:'review',rejectedAnswers:[]}};
const bankChild={...bankHelp,number:2,acceptedAnswers:['children'],bankEntry:'child'};
assert.equal(compare([bankHelp,bankChild],{'1.1':'to help','2.1':'children'}).bankConflicts.length,0);
let reused=compare([bankHelp,bankChild],{'1.1':'to help','2.1':'to be helping'});
assert.equal(JSON.stringify(reused.bankConflicts),JSON.stringify([{entry:'help',numbers:[1,2]}]));
assert.equal(reused.matched,1);assert.equal(reused.review,1);
assert.equal(compare([bankHelp,bankChild],{'1.1':' TO  HELP ','2.1':'to BE helping'}).bankConflicts.length,1);
assert.equal(compare([bankHelp,bankChild],{'1.1':'helpful','2.1':'helpful'}).bankConflicts.length,0);
assert.equal(compare([bankHelp,{...bankChild,bankReuse:undefined}]).available,false);
assert.equal(compare([{...bankHelp,bankReuse:'unknown'},bankChild]).available,false);
assert.equal(compare([bankHelp,{...bankChild,bankEntry:'help'}]).available,false);
assert.equal(compare([bankHelp,{...bankChild,bankEntry:'HELP'}]).available,false);
assert.equal(compare([bankHelp,{...bankChild,acceptedAnswers:['to help']}]).available,false);
assert.equal(compare([{...exactTwo,fillMarking:{...exactTwo.fillMarking,wordCountAmbiguity:undefined}}]).available,false);
assert.equal(compare([{...exactTwo,acceptedAnswers:['instead']}]).available,false);
// Integrate with every actual new complete group; exercise all alternate forms.
const page=fs.readFileSync(path.join(__dirname,'../../../build/english-benchmark-quality-review/index.html'),'utf8');
const data=JSON.parse(page.match(/<script id="quality-data" type="application\/json">(.*?)<\/script>/s)[1]);
let groups=0,responses=0,alternatives=0,actualOnceBanks=0;
for(const g of Object.values(data.groups).filter(g=>g.questions.some(q=>q.acceptedAnswers))){
 const saved=Object.fromEntries(g.questions.map(q=>[q.number+'.1',q.acceptedAnswers[0]]));
 assert.equal(compare(g.questions,saved).matched,g.questions.length);
 for(const q of g.questions){
  for(const form of q.acceptedAnswers){assert.equal(compare(g.questions,{...saved,[q.number+'.1']:form.toLowerCase()}).matched,g.questions.length);alternatives++;}
  for(const wrong of q.fillMarking.rejectedAnswers)assert.equal(compare(g.questions,{...saved,[q.number+'.1']:wrong}).different,1);
 }
 if(g.questions[0].bankReuse==='once'){
  const repeated=compare(g.questions,{...saved,'2.1':g.questions[0].acceptedAnswers[0]});
  assert.equal(repeated.bankConflicts.length,1);assert.equal(repeated.bankConflicts[0].entry,g.questions[0].bankEntry);
  assert.equal(repeated.bankConflicts[0].numbers.join(','),'1,2');assert(repeated.matched<g.questions.length);actualOnceBanks++;
 }
 groups++;responses+=g.questions.length;
}
assert(groups>=7);assert(responses>=48);
let pendingClauses=0;
let pendingPastForms=0;
for(const [id,clauses]of [
 ['grade10-grammar-library-cinema-neighbour',['who was carrying','that was carrying']],
 ['grade10-grammar-bakery-watercolour-train',['who was pushing','that was pushing']],
 ['grade10-grammar-hospital-birdwalk-bus',['who was standing','that was standing']]
]){
 const g=data.groups[id];assert(g);
 const saved=Object.fromEntries(g.questions.map(q=>[q.number+'.1',q.acceptedAnswers[0]]));
 for(const clause of clauses){const row=compare(g.questions,{...saved,'8.1':clause});assert.equal(row.matched,9);assert.equal(row.review,1);assert.equal(row.different,0);pendingClauses++;}
 const pastForm={'grade10-grammar-library-cinema-neighbour':'carried','grade10-grammar-bakery-watercolour-train':'pushed','grade10-grammar-hospital-birdwalk-bus':'stood'}[id];
 const pastResult=compare(g.questions,{...saved,'8.1':pastForm});assert.equal(pastResult.matched,9);assert.equal(pastResult.review,1);assert.equal(pastResult.different,0);pendingPastForms++;
}
console.log(JSON.stringify({passed:true,cases:64+pendingClauses+pendingPastForms,actual_fill_groups:groups,actual_fill_positions:responses,accepted_forms_checked:alternatives,actual_once_banks_reuse_checked:actualOnceBanks,known_variants_reuse_same_root:true,no_unknown_root_stemming:true,given_form_scope_clauses_need_review:pendingClauses,past_form_exclusions_need_review:pendingPastForms,no_three_answer_cap:true,unknown_not_marked_wrong:true,per_slot_word_limits:true,minimum_word_limits:true,unchanged_whole_keyword:true,unlisted_contraction_hyphen_wordcounts_need_review:true,multiword_forms_preserved:true,full_group_contract:true,local_not_production:true}));
