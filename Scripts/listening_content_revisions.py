"""Owner-requested listening comprehension revisions; historical snapshots stay frozen.

Explicitly authored English questions preserve the original correct option IDs.
Primary 1/2 picture/introductory tasks keep their age-appropriate Chinese directions.
"""
PROMPTS = {
's1.astra.a13': 'Which suggestion best addresses the speaker\'s difficulty?',
's1.astra.b15': 'Where and when will they meet?',
's1.astra.b02': 'Which books should be put by the window?',
's1.astra.b05': 'How would the speaker answer a friend who asks, "You enjoyed the film, didn\'t you?"',
's1.astra.b18': 'Which note accurately records the project update?',
's1.second.c16': 'Which booking does the guest finally confirm?',
's2.astra.second.q14': 'Why has the speaker not decided whether to join the walk?',
's2.astra.second.q15': 'What do the speakers mainly disagree about?',
's2.astra.second.q16': 'Which reply accurately acknowledges the speaker\'s difficulty and invites them to explain where they got stuck?',
's2.astra.second.q17': 'What do the speakers finally agree to do?',
's2.astra.second.q18': 'Which note distinguishes the speaker\'s original plan from what actually happened?',
's3.second.q01': 'What arrangement does the second speaker finally suggest?',
's3.second.q04': 'What does the workshop offer free of charge?',
's3.second.q07': 'What do the speakers still need to compare?',
's3.second.q10': 'What do the speakers decide to discuss next?',
's3.second.q14': 'What is the speaker\'s main point about school communications?',
'cet4.astra.a02': 'When and where should participants attend the workshop?',
'cet4.astra.b02': 'What does the speaker promise to do if the part does not arrive today?',
'cet4.astra.a14': 'What is the speaker\'s attitude towards the new system?',
'cet4.astra.b14': 'What is the speaker\'s main point about the new schedule?',
'cet6.second.01': 'Under what condition would the speaker support a shared-workspace trial?',
'cet6.second.02': 'What is the second speaker mainly questioning?',
'cet6.second.03': 'Which statement best describes the current findings?',
'cet6.second.07': 'What is the speaker\'s current view of the plan?',
'cet6.second.09': 'What action does the speaker recommend?',
'cet6.second.13': 'What does the speaker recommend doing next?',
'cet6.second.14': 'Why does the second speaker hesitate to recommend a plan?',
'cet6.second.15': 'What does the speaker see as the article\'s main weakness?',
'adv.astra.a11': 'How does the speaker interpret the difference in attendance?',
'adv.astra.a12': 'What is the speaker\'s current position on the proposed launch date?',
'adv.astra.b11': 'Which statement should be recorded in the corrected minutes?',
'adv.astra.b12': 'Which statement preserves the speaker\'s distinction between short-term and long-term effects?',
'adv.astra.second.c01': 'Which note accurately records the speaker\'s current judgement?',
'adv.astra.second.c02': 'What conclusion does the change in the analysis support?',
'adv.astra.second.c03': 'Which statement should appear in the corrected final minutes?',
}
OPTIONS = {
's1.astra.b15': ['At the library at two tomorrow.', 'At the cafe next to the library at two tomorrow.', 'At the cafe at two today.'],
's1.astra.b02': ['All the books.', 'The books with red labels.', 'The books without red labels.'],
's1.astra.b18': ['Tested on Monday; login fixed; sound still being checked.', 'Tested on Monday; sound fixed; login still being checked.', 'Repairs on Monday; login and sound fixed; testing still in progress.'],
's1.second.c16': ['Friday to Sunday, without hotel breakfast.', 'Friday to Saturday, without hotel breakfast.', 'Friday to Saturday, with hotel breakfast.'],
's2.astra.second.q14': ['To check how many steps the route has before deciding, because of a sore ankle.', 'To wait for the price to fall to an affordable level.', 'To wait for friends to suggest a more appealing activity.'],
's2.astra.second.q15': ['Whether most people already travel by electric bus.', 'Whether the change is likely to happen within ten years.', 'Whether charging stations should be built later despite the change happening within ten years.'],
's2.astra.second.q17': ['Do their own activities first, then meet at the cafe at four for a drink.', 'Sketch by the river together, visit the exhibition at four, then go to the cafe.', 'Visit the exhibition together, then do separate activities and cancel the cafe meeting.'],
's2.astra.second.q18': ['The speaker caught the planned early bus but was delayed by its slow journey.', 'The speaker missed the planned early bus after going home for a wallet, then took the next bus.', 'The speaker switched from the next bus to the early bus, then lost a wallet on it.'],
's3.second.q01': ['Cancel the event because there are too few helpers in the afternoon as well.', 'Keep the event and move its start to after lunch.', 'Keep the event on Saturday morning as planned.'],
's3.second.q04': ['Teaching; participants pay only if they use materials supplied by the organisers.', 'Teaching and all materials supplied by the organisers.', 'Materials; everyone must pay a teaching fee.'],
's3.second.q07': ['Whether the total number of cups was lower this year.', 'Whether fewer people attended this year.', 'How many cups were used per visitor in each year.'],
's3.second.q10': ['Where pupils can ask for a rest.', 'How to arrange the food stalls.', 'Which sports events to keep.'],
's3.second.q14': ['Use mainly paper notices and reduce other channels.', 'Choose the channel to suit the message and the people receiving it.', 'Use mainly phone calls so that no information is missed.'],
'cet4.astra.a02': ['At one in Room Six.', 'At two in Room Six.', 'At two in Room Nine.', 'At one in Room Nine.'],
'cet4.astra.b02': ['Begin repairs anyway and return the bike tomorrow morning.', 'Call by five to confirm that the bike will be ready tomorrow morning.', 'Call by five to discuss another repair date if the part arrives today.', 'Call by five to discuss another repair date.'],
'cet4.astra.a14': ['The search function is useful, but the old sharing tool should be kept for now.', 'The sharing function is useful, but the old search tool should be kept for now.', 'The search function is useful, so the old sharing tool should also be replaced now.', 'The search function is poor, so the old sharing tool should be kept for now.'],
'cet4.astra.b14': ['The early feedback is positive, so the schedule should be kept despite the few replies.', 'Few people have replied and most dislike it, so more feedback is needed.', 'The schedule has already been retained, and only implementation suggestions are needed.', 'The early feedback is positive, but more replies are needed before making a decision.'],
}
# Each replacement checks meaning rather than reproducing the entire transcript.
# Tuple: question, options A/B/C, correct ID, explanation.
REPLACEMENTS = {
('companion.senior1.window-rainbow','s1.second.c18'): (
 'What should the listener do before explaining an answer to a partner?',
 ['Read the question again.', 'Ask the partner to write the answer.', 'Explain the answer before reading the question.'], 'a',
 '录音要求先再次读题，再向同伴解释答案；b加入未提到的写作任务，c颠倒顺序。'),
('companion.senior2.shadow-boats','s2.astra.second.q13'): (
 'What does the speaker want to know?',
 ['Where the listener has been waiting.', 'How much longer the listener plans to wait.', 'How much time the listener has already spent waiting.'], 'c',
 'How long have you been waiting询问已持续等待的时长；不是地点，也不是未来还打算等多久。'),
('companion.senior3.paper-boat','s3.second.q03'): (
 'What was happening when the speakers arrived?',
 ['The bridge inspection had already finished.', 'The bridge was under inspection.', 'The speakers were beginning their journey to the bridge.'], 'b',
 'was being inspected说明到达时桥正在接受检查；a错把正在进行说成完成，c改变到达的时间关系。'),
('companion.senior3.paper-boat','s3.second.q12'): (
 'How does this route compare with the other two routes they tried?',
 ['It is shorter than both of them.', 'It is longer than both of them.', 'It is shorter than one but longer than the other.'], 'a',
 'the other two routes表示比较对象包括另外两条，当前路线比两条都短；不要求逐字复述。'),
('companion.undergraduate.small-mountain','cet4.astra.b08'): (
 'What does the speaker ask the listener to save?',
 ['Only a link.', 'A copy, rather than just a link.', 'A link instead of a copy.'], 'b',
 'not just a link限定只存链接不够，需要保存副本；a和c均漏掉所需副本。'),
('companion.undergraduate.small-mountain','cet4.astra.second01'): (
 'Which session has changed rooms?',
 ['Every session.', 'Only the afternoon session.', 'Only the morning session.'], 'c',
 'Only限定仅上午场移到小房间，不代表下午场或所有场次移动。'),
('companion.postgraduate.missing-piece','cet6.second.08'): (
 'What limitation of the figures does the speaker identify?',
 ['They leave seasonal changes out of account.', 'They fully account for seasonal changes.', 'They describe only seasonal changes.'], 'a',
 'do not take seasonal changes into account明确指出没有计入季节变化；b反转否定，c误称只描述季节变化。'),
('companion.postgraduate.missing-piece','cet6.second.10'): (
 'How does the speaker assess the results?',
 ['They are discouraging and should be discarded.', 'They establish a firm conclusion.', 'They are promising but do not establish a firm conclusion.'], 'c',
 'encouraging表示令人鼓舞，far from conclusive表示尚不能定论；c同时保留两层判断。'),
('companion.advanced.paper-moon','adv.astra.b17'): (
 'What distinction does the speaker make about the report?',
 ['It established a causal relationship rather than an association.', 'It reported an association without establishing causation.', 'It found no association between the factors.'], 'b',
 'not a proven cause排除已证明因果关系；a反转该限制，c误删已报告的关联。'),
('marcus.primary3.family-photo-wall','sister-word'): (
 'Who is being introduced?', ['A sister.', 'A brother.', 'A mother.'], 'a',
 'sister指姐妹；brother是兄弟，mother是母亲。根据听到的亲属关系选择，不要求整句拼写。'),
('oliver.primary3.reading-circle','name-link'): (
 'What does the speaker say about their relationship with the listener?', ['They are neighbours.', 'They are friends.', 'They are cousins.'], 'b',
 'your friend表明是朋友；录音未说邻居或表亲。不要求逐字复述。'),
('ruby.primary3.beach-welcome','i-am'): (
 'What is the speaker doing?', ['Saying hello.', 'Saying thank you.', 'Saying goodbye.'], 'c',
 'Goodbye用于告别；不是问候或道谢。根据交际功能选择，不要求拼写。'),
}
PRIMARY3_PROMPTS = {
('marcus.primary3.family-photo-wall','my-mother'): 'Which sentence do you hear?',
('oliver.primary3.reading-circle','hello'): 'Which greeting do you hear?',
('ruby.primary3.beach-welcome','morning'): 'Which greeting does Ruby use?',
}


def revise(unit):
    import copy
    unit = copy.deepcopy(unit)
    changed = []
    for q in unit['questions']:
        key = (unit['id'], q['id'])
        if q['type'] == 'dictation':
            prompt, choices, answer, explanation = REPLACEMENTS[key]
            q['type'] = 'listeningChoice'
            q['prompt'] = prompt
            q['options'] = [dict(id=chr(97+i),text=text) for i,text in enumerate(choices)]
            q['answer'] = answer
            q['explanation'] = explanation
            q['hint'] = '听清录音的意思及限定信息，再选择最符合的一项。'
            q['instruction'] = '听后选择'
            q['difficultyReason'] = '听力理解替代整句听写；保留原材料和能力支点，通过语义差异作答。'
            del q['acceptedAnswers'], q['normalization']
        elif q['type'] == 'listeningChoice':
            if q['id'] in PROMPTS:
                q['prompt'] = PROMPTS[q['id']]
                if q['id'] in OPTIONS:
                    assert len(OPTIONS[q['id']]) == len(q['options'])
                    for option,text in zip(q['options'],OPTIONS[q['id']]):option['text']=text
            elif key in PRIMARY3_PROMPTS:q['prompt']=PRIMARY3_PROMPTS[key]
        else:continue
        changed.append(q['id'])
    return unit, changed
