"""Build a separate KS1 band reference without manufacturing product-grade cells."""
import hashlib
import json
import os
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from band_phonics_contract import validate_draft


def build(index_ref, output):
    index=json.loads(load_ref(index_ref).read_text())
    assert index['band_reference_only'] and index['individual_grade'] is None
    assert index['grade_specific_coverage_counted'] is False and len(index['groups'])==3
    groups=[]
    for row in index['groups']:
        d=json.loads(load_ref(row['manuscript']).read_text());validate_draft(d)
        a=json.loads(load_ref(row['audio_manifest']).read_text())
        assert a['manuscript']==row['manuscript'] and a['whole_final_audio_decode_passed']
        assert a['band_reference_only'] and a['individual_grade'] is None and len(a['tracks'])==1
        t=a['tracks'][0];path=load_ref(t)
        assert t['response_numbers']==list(range(1,10)) and t['repeat_count']==1
        assert 0<t['observed_English_word_tokens_per_minute']<113
        assert all(t['path']!=o.get('source',{}).get('path') for o in index.get('sources',[]))
        groups.append(dict(id=d['id'],title=d['title'],lists=d['lists'],questions=d['clips'][0]['questions'],turns=d['clips'][0]['turns'],
                           instruction=d['instruction'],local_rate_notice=d['local_rate_notice'],measured_rate=t['observed_English_word_tokens_per_minute'],
                           audio_url=os.path.relpath(path,output.parent),audio_asset={k:t[k] for k in ['path','sha256','bytes']},
                           manuscript=row['manuscript'],audio_manifest=row['audio_manifest']))
    data=dict(index=index_ref,band_reference_only=True,individual_grade=None,grade_specific_coverage_counted=False,groups=groups,
              whole_originals=3,responses=27,source_audio_acquired=False)
    encoded=json.dumps(data,ensure_ascii=False).replace('<','\\u003c').replace('>','\\u003e').replace('&','\\u0026')
    script=(BASE/'Tools/band_phonics_review.js').read_text()
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>KS1 学段补充试做</title><style>
*{box-sizing:border-box}body{margin:0;background:#f3f5ef;color:#213631;font:16px/1.65 system-ui,sans-serif}main{max-width:900px;margin:24px auto;padding:24px}article{background:#fffefa;border:1px solid #dce5dd;border-radius:16px;padding:24px}h1{font-size:26px}p{margin:12px 0}.muted{color:#62746c;font-size:14px}table{width:100%;border-collapse:collapse;font:20px/1.8 Georgia,serif;margin:20px 0}th,td{padding:16px;border:1px solid #dce5dd;vertical-align:top}td{width:50%}input{width:2.2em;border:1px solid #789487;border-radius:5px;text-align:center;font:inherit;padding:4px}label{white-space:nowrap}.example{font-size:17px}button,select{font:inherit;border:1px solid #b7cabe;border-radius:8px;padding:9px;background:white;color:#213631}button{cursor:pointer}audio{width:100%;margin:16px 0}.actions{display:flex;gap:10px;flex-wrap:wrap}#teacher{border-top:1px solid #dce5dd;margin-top:20px;padding-top:20px}a{color:#2b6151}[hidden]{display:none!important}:focus-visible{outline:3px solid #d8a84e;outline-offset:3px}@media(max-width:600px){main{padding:12px}article{padding:12px}th,td{padding:9px;font-size:17px}label{white-space:normal}}
</style><main><a href="index.html">返回15档题型页</a><h1>KS1 学段补充试做</h1>
<p>三道完整原创，每道一段双人对话、两列清单、9处字母填空和一个已解示例。只补 p 或 b。</p>
<p class="muted">来源是香港教育局 KS1 教学活动参照（P1—3学段），不是内地某一年级普通考试或现行非纸笔测评；这3稿27响应单独计量，不增加15档年级覆盖。原题脚本与参考键在库，原音频未取得。未经过独立教研、儿童试做、商用或生产验证。</p>
<article><label>选择原创版本 <select id="variants" aria-label="选择学段原创版本"></select></label><h2 id="title"></h2><p id="instruction"></p>
<audio id="audio" controls preload="metadata" aria-label="完整原创双人对话"></audio><p class="muted" id="rate"></p><table id="lists" aria-label="两人的完整清单"></table>
<div class="actions"><button id="compare" type="button">核对9处答案</button><button id="reveal" type="button">查看答案与完整脚本</button><button id="reset" type="button">重新填写</button></div><p id="result" role="status" aria-live="polite"></p>
<section id="teacher" hidden><h3>逐空依据</h3><div id="teacher-body"></div></section></article>
<p class="muted">p/P/全角字母同等接受，另一候选字母与录音不同；填完整单词或其他字符会提示不符合本题字母候选。参考答案不会延伸成开放填空判错规则。输入只留在当前页面，刷新清除。</p>
<p class="muted">参考：<a href="https://www.edb.gov.hk/en/curriculum-development/kla/eng-edu/references-resources/resource%20pri_listening.html">香港教育局小学听力资源</a>，Phonics Dictation: A Shopping List。多数残词可借拼写推断，不能把本形式视为纯听觉辨音效果证明。原创三稿主题为野餐、美术用品和玩具，宽泛主题及部分词汇可与已有稿复现，不算独立难度标定。</p>
<script id="band-data" type="application/json">__DATA__</script><script>__SCRIPT__</script></main></html>'''.replace('__DATA__',encoded).replace('__SCRIPT__',script)
    output.write_text(page)
    return dict(index=index_ref,url='ks1-band-reference.html',whole_originals=3,responses=27,
                band_reference_only=True,grade_specific_coverage_counted=False)


def check(page):
    data=json.loads(re.search(r'<script id="band-data" type="application/json">(.*?)</script>',page.read_text(),re.S)[1])
    assert data['band_reference_only'] and data['individual_grade'] is None and not data['grade_specific_coverage_counted']
    assert len(data['groups'])==data['whole_originals']==3 and data['responses']==27
    for g in data['groups']:
        d=json.loads(load_ref(g['manuscript']).read_text());validate_draft(d)
        a=json.loads(load_ref(g['audio_manifest']).read_text());t=a['tracks'][0]
        assert g['audio_asset']=={k:t[k]for k in ['path','sha256','bytes']}
        assert (page.parent/g['audio_url']).resolve()==load_ref(g['audio_asset'])
        assert g['questions']==d['clips'][0]['questions'] and g['lists']==d['lists'] and g['turns']==d['clips'][0]['turns']
    return dict(whole_originals=3,responses=27,grade_cell_increment=0,audio_assets=3)
