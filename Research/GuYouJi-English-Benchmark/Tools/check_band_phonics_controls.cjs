const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {compareLetter}=require('./band_phonics_review.js');
const samples=[['p','p','match'],['P','p','match'],['ｐ','p','match'],[' Ｂ ','b','match'],['b','p','different'],['B','p','different'],['','p','unanswered'],['  ','b','unanswered'],['pear','p','invalid'],['p/b','p','invalid'],['pb','p','invalid'],['d','p','invalid'],['𝑝','p','match'],['р','p','invalid']];
for(const [value,key,expected]of samples)assert.equal(compareLetter(value,key),expected,JSON.stringify({value,key}));
const base=path.resolve(__dirname,'..');
const index=JSON.parse(fs.readFileSync(path.join(base,'CompleteCoverage20261017/BandPhonicsOriginals-v0.1.json')));
let forms=0;
for(const row of index.groups){const d=JSON.parse(fs.readFileSync(path.join(base,row.manuscript.path)));for(const q of d.clips[0].questions){const key=q.acceptedAnswers[0];for(const value of [key,key.toUpperCase(),key==='p'?'ｐ':'ｂ']){assert.equal(compareLetter(value,key),'match');forms++;}assert.equal(compareLetter(key==='p'?'b':'p',key),'different');}}
console.log(JSON.stringify({synthetic_cases:samples.length,actual_slots:27,actual_normalized_forms:forms,wrong_letter_cases:27,closed_candidates_only:true,general_fill_marking_unchanged:true}));
