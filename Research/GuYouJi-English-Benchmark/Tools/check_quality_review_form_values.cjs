const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');const s=fs.readFileSync(path.join(__dirname,'quality_review_interactions.js'),'utf8'),ctx=vm.createContext({});vm.runInContext(s.slice(s.indexOf('function closedSelectionComparison('),s.indexOf('\nfunction clearSelectionComparison('))+'\nthis.compare=answerComparison;',ctx);
const base={version:1,review:'author_context_checked',sourceBound:true,unknownSyntax:'review',maxWords:3,numberAllowance:'one',unlisted:'review',rejectedAnswers:[]};let cases=0;
const metric={number:1,options:[],acceptedAnswers:['0.6 m','60 cm','0.60 metres wide'],fillMarking:{...base,normalization:'metric_length_v1',metricMillimetres:600,dimensionAxis:'width'}};
const money={number:1,options:[],acceptedAnswers:['1250','1,250','£1250.00'],fillMarking:{...base,normalization:'sterling_amount_v1',sterlingPence:125000,currencyPrinted:'£'}};
const postcode={number:1,options:[],acceptedAnswers:['KT4 8QZ'],fillMarking:{...base,normalization:'uk_postcode_v1'}};
function state(q,value,expected){const r=ctx.compare([q],{'1.1':value});assert.equal(r.available,true);assert.equal(r.rows[0].state,expected,value);cases++;}
for(const v of ['0.6m','0.60000 metres','60 cm','60.000 cm wide','０．６０ｍ'.replace('ｍ','m'),'600/1000 meter','3/5 m','0.6 metres wide'])state(metric,v,'match');
for(const v of ['0.5m','60m','6cm','0m','0.6m high','0.6metres deep'])state(metric,v,'different');
for(const v of ['sixty centimetres','0.6','0.6 m in width','3/0 m','0.6 yards','0,6m','-0.6m','0.6m?','0.6m/','1e-1m'])state(metric,v,'review');
const half={...metric,acceptedAnswers:['0.5m'],fillMarking:{...metric.fillMarking,metricMillimetres:500,dimensionAxis:'height'}};for(const v of ['½ m','1/2m','50cm high','50cms deep','0.500 meter'])state(half,v,'match');
const quarter={...half,acceptedAnswers:['0.75m'],fillMarking:{...half.fillMarking,metricMillimetres:750}};for(const v of ['¾m','3/4 metres','75cm deep'])state(quarter,v,'match');
for(const v of ['1250','1,250','£1,250.00','1250.0 pounds','1250 GBP','１２５０．００','£ 1,250','001250.00'])state(money,v,'match');
for(const v of ['125','1250.01','0','£1251','1,205'])state(money,v,'different');
for(const v of ['1,25','12,50','££1250','1.250','one thousand pounds','1250 dollars','1 250','£1250!','1250/1'])state(money,v,'review');
for(const v of ['kt4 8qz','KT48QZ','KT4   8QZ','ＫT4 8QZ'.replace('Ｋ','K'),'KT４ ８QZ'])state(postcode,v,'match');for(const v of ['KT4 8QA','KT4 9QZ'])state(postcode,v,'different');for(const v of ['KT4-8QZ','KT4 8QZ.','somewhere'])state(postcode,v,'review');
for(const q of [metric,money,postcode]){state(q,'','unanswered');for(const name of ['sourceBound','numberAllowance','unknownSyntax','maxWords']){const bad=structuredClone(q);delete bad.fillMarking[name];assert.equal(ctx.compare([bad]).available,false);cases++;}}
for(const q of [{...metric,acceptedAnswers:['0.5m']},{...metric,fillMarking:{...metric.fillMarking,rejectedAnswers:['60cm']}},{...money,fillMarking:{...money.fillMarking,rejectedAnswers:['£1,250']}},{...money,fillMarking:{...money.fillMarking,currencyPrinted:'$'}},{...postcode,acceptedAnswers:['KT4 8QZ','KT48QZ']}]){assert.equal(ctx.compare([q]).available,false);cases++;}
console.log(JSON.stringify({passed:true,cases,exact_metric_rationals:true,axis_preserved:true,currency_bound:true,postcode_whitespace_only:true,unknown_review:true,no_three_answer_cap:true,source_limits_not_generalized:true}));
