import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
const [directory,destination]=process.argv.slice(2);if(!directory||!destination)throw Error('private-output report-path');
const rows=readFileSync(join(directory,'ledger.jsonl'),'utf8').trim().split('\n').map(JSON.parse),requests=new Map();
for(const row of rows){if(row.kind==='dispatch')requests.set(row.key,{key:row.key,upperUSD:row.upperUSD,at:row.at});if(row.kind==='receipt'){const old=requests.get(row.key);if(old)requests.set(row.key,{...old,...row});}}
let actualUSD=0,unknownUpperUSD=0,cachedTokens=0,promptTokens=0,completionTokens=0;
const unresolved=[];
for(const r of requests.values()){
 if(typeof r.costUSD==='number')actualUSD+=r.costUSD;else{unknownUpperUSD+=r.upperUSD;unresolved.push({key:r.key,upperUSD:r.upperUSD,status:r.status??'no receipt'});}
 cachedTokens+=r.usage?.prompt_tokens_details?.cached_tokens??0;promptTokens+=r.usage?.prompt_tokens??0;completionTokens+=r.usage?.completion_tokens??0;
}
const report={currency:'CNY',usdCny:7.2,budgetCNY:25,requests:requests.size,actualCNY:actualUSD*7.2,unresolvedUpperCNY:unknownUpperUSD*7.2,accountedCNY:(actualUSD+unknownUpperUSD)*7.2,unresolved,promptTokens,cachedTokens,completionTokens,scope:'Offline library planning, rejected drafts, production and review in the shared ledger; excludes Codex usage and the earlier standalone ten-person pilot.'};
writeFileSync(destination,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
