#!/usr/bin/env python3
"""Audit 13 selected material/option views and exact/near text-family signals.

Does not verify answer semantics, rights, original-PDF completeness or student fit.
Near overlap only nominates a human review; never silently merges answer keys.
"""
import hashlib,json,re
from pathlib import Path
from grade_mode_evidence import BASE,REPO,CURRENT_BATCHES,load_ref
from profile_cloze_reference_batch import CASES
from profile_task_load import count,TOKENS

EXTRA=[
 (7,'grade7-wuhan2025-21cnjy23303148','cloze','This February, our family','\n11. A. experience',list(range(11,26)),'underscored'),
 (7,'grade7-hefei2025-21cnjy26607976','clozeA','Dear Betty,\nIt is','\n31. A. sad',list(range(31,41)),'underscored'),
 (7,'grade7-hefei2025-21cnjy26607976','clozeB','Hello! My','\n41. A. bag',list(range(41,51)),'underscored'),
 (8,'grade8-hubei2026-21cnjy26105408','cloze','My anger exploded','\n1. A．took',list(range(1,16)),'underscored'),
 (12,'grade12-tianjinlower2025-21cnjy22402528','cloze','Once upon a time, a greedy','\n16. A. cage',list(range(16,36)),'underscored'),
 (11,'grade11-tianjin2026-21cnjy26082071','cloze','Twenty years ago','\n31. A. interfere',list(range(31,51)),'underscored'),
]

def normalized(text):
    text=re.sub(r'_+\d+_+',' ',text)
    return ' '.join(TOKENS.findall(text)).lower()

def shingles(text,n=5):
    words=text.split()
    return {tuple(words[i:i+n]) for i in range(max(0,len(words)-n+1))}


if __name__=='__main__':
    manifest=json.loads(CURRENT_BATCHES.read_text())
    batches=[json.loads(load_ref(r).read_text()) for r in manifest['batches']]
    papers={p['id']:p for b in batches for p in b['papers']}
    records=[];bodies={};confirmations=[]
    for grade,pid,local,start,end,ids,style in list(CASES)+EXTRA:
        p=papers[pid];view=load_ref(p['resource_text']).read_text();first=view.index(start);last=view.index(end,first)
        material=view[first:last].strip();item=next(x for x in p['rows'] if x['id']==pid+'.'+local)
        empty=material
        offsets=[]
        for number in ids:
            pat=r'_+'+str(number)+r'_+' if style=='underscored' else r'\b'+str(number)+r'\b'
            matches=list(re.finditer(pat,material))
            if len(matches)!=1:raise ValueError('Missing/repeated material blank '+pid+'/'+str(number))
            offsets.append((matches[0].start(),matches[0].end(),number))
        if [n for _,_,n in sorted(offsets)]!=ids:raise ValueError('Material blank order changed')
        for begin,finish,_ in sorted(offsets,reverse=True):empty=empty[:begin]+empty[finish:]
        wanted=list('ABCD')[:item['shape']['options_each']]
        option_lines=[]
        for number in ids:
            found=re.search(r'^'+str(number)+r'\s*(?:[.．]\s*|\s+)(.*)$',view[last:],re.M)
            if not found:raise ValueError('Missing option row '+str(number))
            letters=re.findall(r'(?:^|\s)([A-D])[.．]\s*',found[1])
            if letters!=wanted:raise ValueError('Incomplete options '+pid+'/'+str(number))
            option_lines.append(found[0])
        if len(ids)!=item['shape']['responses']:raise ValueError('Response count differs')
        gid=item['id'];bodies[gid]=normalized(empty)
        records.append({'group_id':gid,'grade':grade,'paper_identity':pid,'source_acquisition_id':p['acquisition_id'],
            'source_text':p['resource_text'],'material_line_span_1based':[view[:first].count('\n')+1,view[:last].count('\n')+1],
            'material_sha256':hashlib.sha256(material.encode()).hexdigest(),'options_view_sha256':hashlib.sha256('\n'.join(option_lines).encode()).hexdigest(),
            'normalized_material_sha256':hashlib.sha256(bodies[gid].encode()).hexdigest(),'unfilled_material_counts':count(empty),
            'responses':len(ids),'options_each':len(wanted),'student_minutes':None,'independent_answer_gold':False})
        # Confirms only the selected cloze input, not the surrounding paper.
        confirmations.append({'group_id':gid,'source_text':p['resource_text'],'necessary_input_complete':True,
                              'material_sha256':records[-1]['material_sha256'],'options_view_sha256':records[-1]['options_view_sha256'],
                              'scope':'selected_cloze_material_all_numbered_blanks_all_option_rows; source instruction reviewed in paper block; not key correctness'})
    comparisons=[];ids=list(bodies)
    for i,a in enumerate(ids):
        for b in ids[i+1:]:
            x,y=shingles(bodies[a]),shingles(bodies[b]);j=len(x&y)/len(x|y) if x|y else 0
            comparisons.append({'left':a,'right':b,'exact_normalized_match':bodies[a]==bodies[b],'fivegram_jaccard':j,
                                'manual_review_candidate':j>=0.5,'threshold_is_engineering_screen_not_family_truth':True})
    # Concrete contamination probes: renumbering keeps a family; negation does
    # not license transferring an answer even when text remains near-identical.
    sample=bodies[ids[0]];probe_original='A school has ___1___ red seats.';probe_reindexed='A school has ___99___ red seats.'
    assert normalized(probe_original)==normalized(probe_reindexed)
    x,y=shingles(sample),shingles(sample+' not');probe_overlap=len(x&y)/len(x|y)
    assert sample!=sample+' not' and probe_overlap>=0.5
    report={'version':'0.1','scope':'13_selected_new_public_text_clozes_only','records':records,'comparisons':comparisons,
            'exact_repeated_pairs':sum(x['exact_normalized_match'] for x in comparisons),
            'manual_review_candidates':sum(x['manual_review_candidate'] for x in comparisons),
            'all_benchmark_deduplication_complete':False,'model_called':False,
            'probes':{'blank_renumbering_same_family':True,'near_text_not_answer_equivalence':True}}
    out=REPO/'build/english-benchmark-research-20261012/cloze-material-audit20261015-v0.1.json';out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    overlay={'version':'0.1','scope':'explicit_selected_cloze_input_confirmation_not_answers_or_rights',
             'audit':{'path':str(out.relative_to(REPO)),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()},'confirmations':confirmations}
    target=BASE/'FirstRelease/Sampling/input-confirmations-v0.1.json'
    payload=json.dumps(overlay,ensure_ascii=False,indent=2)+'\n'
    if target.exists() and target.read_text()!=payload:raise ValueError('Do not overwrite different confirmation overlay')
    if not target.exists():target.write_text(payload)
    print(json.dumps({'materials':len(records),'pair_checks':len(comparisons),'exact_repeated_pairs':report['exact_repeated_pairs'],
                     'review_candidates':report['manual_review_candidates'],'maximum_pair_jaccard':max(x['fivegram_jaccard'] for x in comparisons),
                     'counts':[(x['grade'],x['responses'],x['unfilled_material_counts']['english_digit_tokens']) for x in records]}))
