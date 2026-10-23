"""Reviewed English presentation copy. Option identities and grading stay frozen.

Audience: junior secondary through advanced learners. Keep conditions, negation,
time and evidence limits; use ordinary English, with no extra answer clues.
Chinese translation exercises and early-primary scaffolding are intentional.
"""

# Unique companion question IDs; named-character units use (unit ID, question ID).
PROMPTS = {
"adv.astra.a03": "During a review, someone says: I can see why speed matters. I'm less clear about how the proposed checks would catch errors before release. What is the main purpose of this comment?",
"adv.astra.a16": "An email says: We can deliver the draft on Friday if the revised figures arrive by noon on Wednesday. Otherwise, we will need to agree a new date. Which summary preserves the full agreement?",
"adv.astra.a17": "A supplier writes: Subject to final testing, we expect the update to be ready by Thursday. This is our current forecast rather than a confirmed release date. Which statement accurately reports this to your team?",
"adv.astra.b01": "A review says: The authors interpret the silence in the interviews as satisfaction. This is plausible, but it relies on an assumption the interviews did not test. What does 'This' refer to?",
"adv.astra.b03": "A manager replies: I'm open to exploring that option. Please bring back a costed proposal before we commit. A colleague wants to buy it immediately. Which reply clarifies what has been authorised?",
"adv.astra.b07": "Read: The new procedure requires two extra checks. This may slow individual cases. Nevertheless, it could reduce the time spent correcting mistakes later. How does the last sentence develop the argument?",
"adv.astra.b09": "You cannot send a table until its figures have been checked, but you are willing to send it afterwards. Which reply explains this process requirement without suggesting unwillingness to cooperate?",
"adv.astra.second.c04": "A partner writes: You may quote my comments on the draft's clarity, provided you identify them as feedback on that draft. Please do not present them as an assessment of the final report, which I have not read. Which internal summary preserves the permitted use?",
"adv.astra.a01": "A report says: Teams that chose the new planning tool missed fewer deadlines than teams using the previous tool. Teams selected their own tools, and their previous performance was not recorded. Which conclusion best fits this evidence?",
"adv.astra.a02": "You have read only Park's review, which says an earlier trial reduced waiting times. You have not found the original report. Which statement accurately identifies the source you consulted?",
"adv.astra.a04": "The minutes say: The panel acknowledged the cost concern but did not endorse postponement. Which statement accurately explains this?",
"adv.astra.a06": "A report says: We are not yet in a position to rule out a recording error, although the readings were consistent across three checks. Which interpretation preserves the limits of the evidence?",
"adv.astra.a09": "A partner asks for 'a representative sample' without saying which people it should represent. You need to confirm the population before preparing the sample. Which reply is most suitable?",
"adv.astra.b04": "A brief needs to report neutrally that twenty people took part and twelve returned questionnaires. No target response count was set. Which sentence avoids adding disappointment or approval?",
"adv.astra.a07": "Two page layouts were tested with only six people each, and completion times varied widely. The report says: The trial did not establish a difference in speed. Which explanation should follow?",
"adv.astra.b06": "Customers tried revised instructions. Ten said they were clearer and ten reported no change. Nobody assessed actual task performance. Which summary is accurate?",
"adv.astra.b02": "An interviewee said: The instructions were clear, but finding the right page took time. Which paraphrase preserves the whole evaluation without claiming to quote it word for word?",
"adv.astra.b05": "A comparison states: Version A took less time to learn. Version B led to fewer mistakes once users had learned it. Neither cost nor long-term use was assessed. Which summary is faithful to the comparison?",
"adv.astra.b08": "A colleague uses daytime noise records to claim a venue is quiet all day and night. You accept the daytime findings but want night-time records before making that wider claim. Which reply best expresses this?",
"adv.astra.b10": "Read: The exclusion of incomplete forms reduced the number of responses analysed. Which more direct version preserves only the original information?",
"cet6.second.06": "Read: The authors argue that shorter meetings may improve focus. You have not verified their view. Which sentence is suitable for reporting it?",
"cet6.second.16": "You suggest publishing the assessment criteria first. Someone replies: So you want us to delay the project indefinitely? Which response most accurately clarifies your suggestion?",
"cet6.second.17": "Read: The new process is less time-consuming than the previous one, although neither is particularly simple. Which summary preserves the meaning?",
"cet6.second.18": "Someone says: I support longer opening hours, provided staff are not expected to work unpaid overtime. Which reply accurately acknowledges this position and moves the discussion forward?",
"cet6.a01": "Read: People who attended the optional study sessions reported high levels of confidence. The survey did not ask how confident they had felt beforehand. Which summary preserves the limits of the evidence?",
"cet6.a03": "Read: The absence of complaints does not necessarily mean that users are satisfied. Which paraphrase preserves the meaning?",
"cet6.a06": "Someone says: I worry that the proposed changes will reduce access. You do not yet know whether they mean fees or opening hours. Which reply best helps clarify their concern?",
"cet6.b01": "A review says: The proposal is promising, though its long-term effects remain uncertain. Which option best describes the writer's attitude?",
"cet6.b04": "Read: The revised procedure is no less reliable than the original, except when records are incomplete. Which paraphrase preserves the meaning without assuming what happens in the exception?",
"cet6.b06": "Read: Online access removes the need to travel. It does not, however, remove the need for a reliable connection. What is the function of the second sentence?",
"cet6.a13": "A report says: The service received fewer complaints this year, but it also served substantially fewer users. Which follow-up question most directly helps assess whether complaints fell relative to use?",
"cet6.a14": "You are writing formal feedback to a partner. You want to say a conclusion lacks support and ask for further evidence. Which sentence best serves this purpose?",
"cet6.b13": "Read: Of the residents who chose to complete our online survey, 72% favoured the plan. Which report is most faithful to the original?",
"cet6.b18": "At the end of a discussion, both sides have agreed to a trial but have not agreed how to judge success. Which summary is most accurate?",
"s1.astra.a01": "A note says: Try explaining the new idea to a classmate without looking at your notes. This can show you which parts you still need to study. What does 'This' refer to?",
"s1.astra.b03": "Read two messages. Kai: I'm taking the nine o'clock train tomorrow. I've bought my ticket. Mei: I might take that train too, but I haven't decided. Which statement can be recorded as a confirmed travel plan?",
"s1.astra.a05": "The only message in a chat is: The sports hall is open this evening, isn't it? Nobody has replied. You are asked to check before booking. Which message should you send next?",
"s1.astra.b09": "An organiser writes: We're meeting the visitors at four on Friday. Sam says he was told five, but you have not seen an updated notice. Which reply directly explains the conflict and asks the organiser to confirm the final time?",
"s1.astra.a14": "Combine these sentences without changing the relationship: I spoke to a student. Her brother made this model. Which sentence is correct?",
"s1.astra.b14": "You returned the camera you had borrowed from Sam. Which sentence preserves this meaning?",
"s1.astra.a15": "You have arranged to practise with classmates on Saturday morning and are free that afternoon. A friend asks to meet in the morning. Which reply keeps your practice plan and offers a time you can meet that day?",
"s1.astra.a16": "The recording team writes: We have kept our booking for the room where we recorded the interview. We have deleted the recording that we made there. Which note accurately records what happened to the booking and the recording?",
"s1.astra.a18": "The poster is finished and ready to use. The list is still being checked now. Which update preserves both facts?",
"s1.astra.b17": "You know tickets cost five yuan each. A friend asks: The tickets are free, aren't they? Which reply answers the question correctly and then gives the correct information?",
"s1.astra.a02": "A notice says: Students who need a locker should fill in this form. Who needs to fill in the form?",
"s1.astra.b06": "A message says: I'm uploading the photos now. Please wait before opening the link. What can you be sure of?",
"s1.second.c09": "On Sunday, you receive this message: I usually go swimming on Monday evenings, but I'm taking my grandmother to the concert tomorrow evening. We've already got our tickets. What should you put in the calendar for the following Monday evening?",
"s1.astra.b04": "Compare the gaps: (1) the day ___ we arrived; (2) the day ___ we will always remember. Which analysis is correct?",
"s1.second.c13": "Read: (1) The boxes that arrived this morning are in the hall. (2) The boxes that we ordered last month are still missing. Without changing any other words, which use of 'that' can be removed while keeping both sentences grammatical?",
"s2.astra.a17": "A friend says: I was bored during the talk. Which sentence reports the friend's experience without adding a judgement about their personality?",
"s2.astra.r03": "Compare: (1) My friends who live nearby came to dinner. (2) My friends, who live nearby, came to dinner. Consider only how 'live nearby' is used, without inferring actual numbers. Which statement is accurate?",
"s2.astra.b03": "A friend puts down a brush and says: I've been painting the sign. Which point remains uncertain from this sentence alone?",
"s2.astra.r07": "Read two separate messages: Kai decided to join the walk. Mei enjoyed joining the walk. Which conclusion uses only the information provided?",
"s2.astra.r11": "It is Friday. A friend says: I've been walking to the library every morning this week. Which report preserves the activity and time period?",
"s2.astra.a06": "A trial record shows only this: eight of the ten people in this week's trial found the entrance faster. Which summary keeps to this evidence?",
"s2.astra.a16": "Planning a route is easier if the destination is decided in advance. Which sentence keeps this condition and uses an -ing phrase as its subject?",
"s2.astra.r06": "A message says: The knot was difficult, but we didn't stop trying. Which sentence preserves the action described without adding success or failure?",
"s2.astra.r04": "Read the whole message: I tasted the soup and realised I had added too much salt. I mixed in some unsalted soup and tasted it again. It tastes fine now. 'Unsalted' means without added salt. Which reply accurately reflects the final state?",
"s2.astra.b13": "You will be drawing in a quiet gallery from three to four tomorrow and will be free at five. A friend wants to call at half past three. Which reply explains what you will be doing and suggests a possible alternative?",
"s2.astra.b17": "Some parts of a friend's chart are hard to understand. You want to ask for an explanation without judging the friend's ability. Which reply is most suitable?",
"s2.astra.b15": "You prefer short instructions; a friend prefers detailed ones. You want the same readers to compare both versions on the same task without deciding in advance which is better. Which suggestion best expresses this?",
"s2.astra.second.q02": "A handbag is blue and the scarf inside it is red. You took the scarf out of the bag. Which sentence adds the bag's colour in a non-defining clause and preserves the action?",
"s2.astra.second.q03": "Read: I admit damaging the cover, but I didn't do it on purpose. 'On purpose' means intentionally. Which note preserves both parts of the statement?",
"s2.astra.second.q05": "A diary says: Until last Saturday, I had never watched a film outdoors. That evening, I finally did. Which summary is accurate?",
"s2.astra.second.q09": "You want to know whether a friend's planned route tomorrow passes the bakery. If it does, you would like them to collect your bread order, without changing their route. Which message expresses this?",
"s2.astra.second.q10": "A friend says: I haven't been sleeping well lately. I do fall asleep, but I wake up several times each night. Which statement accurately describes their sleep?",
"s2.astra.second.q12": "You want to say that the fact that the room was empty surprised you, rather than something someone said in it. Which sentence expresses this?",
"s3.astra.a03": "A label says: The boxes marked with a blue circle contain glass. There are also unmarked boxes in the warehouse. Based only on the label, which statement follows?",
"s3.astra.b06": "Read: The request needs to be approved by the owner. What does 'to be approved' tell us?",
"s3.astra.b04": "The discussion did not solve every problem, but it helped both sides understand each other's concerns. Which sentence preserves this relationship and scope?",
"s3.astra.a13": "A friend suggests writing: All the windows have been repaired. Records confirm repairs to only four of ten windows; the rest have not been checked. Which reply is accurate and helps revise the report?",
"s3.astra.a14": "Read: At nine, I was reading the message. I had saved a copy at eight. What can be concluded from these sentences alone?",
"s3.astra.a18": "A record says: We added a diagram to make the route clearer. There is no further feedback. Which summary is most cautious and accurate?",
"s3.astra.b16": "A friend says: The screen went dark after we opened the file, so the file must have caused it. The only evidence is the order of events. Which reply identifies the limit of this reasoning and helps you work together?",
"s3.astra.b17": "An interview record says: We know that the room is available. What we don't know is whether it is large enough. Which summary accurately states what is known and unknown?",
"s3.astra.b18": "A friend says: I have three reports to read before Friday. Based only on this sentence, which reply correctly understands the task?",
"s3.astra.r01": "The next sentence of a brief is: No one has yet identified who did it. The only confirmed fact is that the tyres of the bicycle by the road were repaired last night. Which sentence accurately introduces this fact and links to the next sentence?",
"s3.astra.r02": "A memory is organised as discovery, earlier cause, then remedy: I reached the entrance and searched my bag for the tickets. ___ So I went back to collect them. The tickets had been put on the kitchen table before departure. Which sentence explains this earlier event without adding another trip home?",
"s3.astra.r03": "A notice says: If the temperature falls below ten degrees, we will move the activity indoors. Later you hear only: The activity has been moved indoors. There is no temperature record, and no claim that cold weather is the only possible reason. Which summary stays within the evidence?",
"s3.astra.r04": "Minutes say: Lea suggested that the library stay open an hour later. The committee said it would discuss the proposal next week. Which summary preserves who proposed what and the current progress?",
"s3.astra.r05": "A diary says: We hurried to the small cinema, only to find that the last showing had been cancelled. How does 'only to find' relate to the first part?",
"s3.second.q02": "A school newspaper collected replies only in a photography club's group chat. Of 30 respondents, 24 wanted the darkroom open at weekends. No other pupils were surveyed. Which sentence is suitable for reporting the result?",
"s3.second.q06": "A parent says: I support giving students more time to read, but who will pay the staff for the extra hours? Which summary accurately states the parent's position before you respond?",
"s3.second.q11": "You are describing a community compost bin. Your only source is the maker's advertisement: Our box can turn food scraps into compost in four weeks. You have not tested it or read an independent test report. Which sentence clearly identifies the source of the claim?",
"s3.second.q16": "A group is discussing turning unused school land into a vegetable garden. Growing vegetables offers practical experience, but watering needs regular helpers. At present, helpers are available only on Wednesdays. Which conclusion addresses both the benefit and the unresolved limit?",
"cet4.astra.a01": "You need one more day to finish a group report. Which message asks your group for agreement without assuming they have already agreed?",
"cet4.astra.a03": "A notice says: The course fee covers all printed materials, but you need to bring your own lunch. What does 'covers' mean here?",
"cet4.astra.a04": "Choose the linking word: The instructions were clear. ____, several users skipped a step and had to start again.",
"cet4.astra.a05": "Read: Only applications received by Friday will be considered. Which sentence preserves the meaning?",
"cet4.astra.a06": "The service is currently available only to local residents. Which sentence expresses this accurately?",
"cet4.astra.b15": "Read: The estimate is conservative: it leaves out several possible sources of income, so the final total may be higher. What does 'conservative' most nearly mean here?",
"cet4.astra.a13": "Someone asks: Could you send me the figures soon? You are willing to help but need an exact deadline. Which reply most directly asks for that missing information?",
"cet4.astra.a15": "Read: The team had two possible designs. After comparing the costs, they settled on the simpler one. What does 'settled on' mean here?",
"cet4.astra.a16": "Read: The website was unavailable for an hour. Several people could not complete their bookings. Which sentence presents the first fact as the cause of the second?",
"cet4.astra.a17": "A message says: I've tried to contact the supplier, but I haven't heard back yet. Which report is accurate?",
"cet4.astra.b01": "A friend asks you to check a document tonight. You cannot do it tonight but can tomorrow morning. Which reply clearly offers that alternative?",
"cet4.astra.b03": "Read: The figures do not support the claim that sales doubled. What does 'support' most nearly mean here?",
"cet4.astra.b04": "Read: We added labels so that visitors could find the right boxes more easily. Which statement is explicitly expressed?",
"cet4.astra.b05": "Read: The hall used to be a warehouse, but it now hosts community events. Which report is accurate?",
"cet4.astra.b06": "More and more residents are choosing to travel by bicycle, but cars are still common. Which sentence accurately expresses this?",
"cet4.astra.b11": "Read: The company plans to open a second shop next spring, subject to approval. Which report preserves the plan, time and approval condition?",
"cet4.astra.b13": "A friend says: We can finish all six interviews in an hour. Each interview takes at least fifteen minutes, and they must be held one at a time. Which reply politely explains the minimum time needed without changing the number or format?",
"cet4.astra.b16": "Read: The team shortened the form and removed two repeated questions. This made it quicker to complete. What does 'This' most naturally refer to?",
"cet4.astra.b17": "Feedback says: The revised guide is easier to follow than the original, though some sections still need work. Which summary is accurate?",
}

CHARACTER_PROMPTS = {
"marcus.junior1.camera-club-kit": {
"q1": "You want to know if Leo has a camera. Which question is correct?",
"q4": "Someone asks, 'Does Eva have a bag?' She does. Which short answer is correct?"},
"marcus.junior1.community-class-board": {
"q1": "You want to know the name of your photography teacher. Which question should you ask?",
"q4": "You enjoy history and find it interesting. Which sentence gives this reason correctly?"},
"marcus.junior2.photo-day-sandwiches": {
"q1": "You need to know the number of bread slices to use. Choose the correct question using 'slices of bread'.",
"q4": "The first two steps are finished. The last step is to put the sandwich in a box. Which sentence clearly marks this final step?"},
"marcus.junior2.photo-project-plans": {
"q1": "Someone asks, 'How are you going to improve your photography?' Which answer explains a method?",
"q4": "Your dream job is photography. Which sentence uses 'want' correctly to express this?"},
"marcus.junior3.neighbourhood-invitations": {
"how-many-come": "You want to ask a neighbour if they know the number of friends who will come. Which question is correct?",
"polite-arrival": "You are writing to a neighbour visiting for the first time. Which question politely asks what time they will arrive?"},
"marcus.junior3.photo-caption-workshop": {
"two-photos": "Marcus took two photos yesterday. Which sentence correctly reports this with 'Two photos' as its subject?",
"which-building": "You are identifying a building repaired last year. Which sentence gives this information correctly?"},
"marcus.junior3.record-corner": {
"singer-writes": "You like singers who write their own music. Which sentence expresses this preference correctly?",
"no-extra-it": "You want a record that you can play at home. Which sentence is correct? Here, a record is a disc for playing music."},
"marcus.senior1.confirm-the-details": {
"q1": "Complete the usual question tag: The light is good, ___?",
"q4": "Someone says, 'He isn't coming, is he?' You know he will definitely come. Which reply matches the facts?"},
"marcus.senior1.project-time-notes": {
"q1": "You finished printing the photos yesterday. Which sentence uses the correct tense for that completed past action?",
"q4": "You organise your camera equipment every Friday. Which sentence describes this regular habit?"},
"marcus.senior2.community-project-brief": {
"collecting-stories": "Use an -ing phrase as the subject to say that gathering stories from local people takes time. Which sentence is grammatical? 'Residents' means people who live in a place.",
"activity-not-ongoing": "You want to describe joint photo editing as an activity within the project, rather than say it is happening right now. Which sentence does this?"},
"marcus.senior2.interview-worktable": {
"avoid-interrupting": "Use 'avoid' to suggest that your interview partner should not interrupt the shop owner. Which sentence has the correct structure? 'Interrupt' means to stop someone while they are speaking.",
"appreciate-waiting": "You want to thank someone for waiting, starting with 'I appreciate'. Which sentence is correct? Here, 'appreciate' expresses thanks."},
"marcus.senior2.portrait-feedback": {
"moving-portrait": "A portrait has a strong emotional effect on you. Which sentence correctly describes both the portrait and your feeling? 'Moved' refers to emotion here, not a change of position.",
"person-can-interest": "You always learn something from a speaker and want to praise her ability to hold your interest. Which sentence expresses this, rather than simply saying that she feels interested?"},
"marcus.senior3.exhibition-purpose": {
"q1": "The photos require checking; they are not doing the checking. Choose the correct passive infinitive.",
"q4": "In 'She was the first person to arrive', what is the main function of 'to arrive'?"},
"marcus.senior3.interview-summary": {
"q1": "Put the question 'Where did she take the photo?' after 'I wonder'. Which sentence is correct?",
"q4": "In 'What she said surprised me', what role does 'What' play?"},
"oliver.junior1.lost-found-desk": {
"q1": "You are holding one key and want to ask if it belongs to the other person. Which question uses the correct singular form?",
"q4": "Someone asks, 'Are these your glasses?' The glasses are yours. Choose the correct short answer."},
"oliver.junior1.reading-room-locations": {
"q1": "Both dictionaries are on the table. Choose the correct answer about their location.",
"q4": "The bag is below the chair, not on it. Which sentence is correct?"},
"oliver.junior2.reading-rhythm": {
"q1": "You want to know how frequently a friend visits the reading club, not how long each visit lasts. Which question should you ask?",
"q4": "You read once on Tuesday and once on Friday, and not on other days. Which sentence accurately describes this frequency?"},
"oliver.junior2.two-reading-spaces": {
"q1": "The two rooms are equally quiet. Choose the correct comparison.",
"q4": "Two people read with equal care. Which sentence is correct?"},
"oliver.junior3.bookclub-enquiries": {
"ask-room": "You are writing to an organiser you do not know well. Use 'Could you tell me' to ask which room the book club uses. Which sentence is correct?",
"booking-order": "You need the organiser to explain the registration process. Which question is grammatical? 'Register' means to sign up."},
"oliver.junior3.bookshop-then-now": {
"former-shelf": "The bookshop sold newspapers in the past but no longer does. Which sentence accurately describes this change?",
"did-you-work": "You want to ask an assistant whether they worked here in the past. Which question is grammatical?"},
"oliver.junior3.repair-labels": {
"daily-check": "The checklist says that someone checks these books every day. Which passive sentence is correct?",
"covers-last-week": "An assistant repaired three covers last week. Which grammatical sentence preserves this fact and starts with 'Three covers'?"},
"oliver.senior1.book-donation-labels": {
"q1": "You welcome books with complete covers. Which sentence clearly shows that the covers belong to the books?",
"q4": "The antecedent is 'the books', and the relative word acts as the subject of its clause. Which expression is complete and grammatical?"},
"oliver.senior1.reader-advice-note": {
"q1": "A reader finds it hard to keep reading regularly. Which sentence offers a small, practical step and explains how it reduces the burden?",
"q4": "You are unsure which method suits a reader. Which sentence gently suggests a method that might help, while preserving that uncertainty?"},
"oliver.senior2.evening-bookshop": {
"eight-thirty": "You are scheduled to read short stories to visitors from eight to nine tomorrow evening. Which sentence uses the future continuous to describe what you will be doing at eight thirty?",
"future-question": "Use the future continuous to ask whether a colleague will be using the upstairs room at nine tomorrow evening. Which question has the correct structure?"},
"oliver.senior2.reading-society": {
"stop-talking": "Someone is still chatting after a discussion begins. You want to ask them to end the chatting, rather than pause another activity in order to chat. Which request is correct?",
"both-starts": "You want to say that discussion of the ending has begun, without emphasising the exact moment it began. In which pair can both sentences express this?"},
"oliver.senior2.restoration-notice": {
"named-room": "The reading room is called the Cedar Room and reopens on Monday. Which sentence correctly adds that it is upstairs in a non-defining clause? 'Cedar Room' is a proper name.",
"whole-event": "You moved an event downstairs, making access easier. Which sentence uses 'which' to refer to that whole change without repeating the subject?"},
"oliver.senior3.archive-time-viewpoint": {
"q1": "The files arrived first; Oliver reached the shop later. Which sentence uses the past perfect to emphasise the earlier arrival?",
"q4": "What is explicitly stated by 'At eight yesterday, I was sorting the papers'?"},
"oliver.senior3.repair-report-focus": {
"q1": "Volunteers repaired three books yesterday. Which sentence starts with 'Three books' and preserves the past time and completed action?",
"q4": "A report says, 'The windows are being replaced.' Which statement repeats only what this explicitly tells us?"},
"ruby.junior1.market-price-talk": {
"q1": "You want to know the price of these two cups. Which question is grammatical?",
"q4": "A customer asks, 'How much is the cup?' Its price tag says $3. Which reply answers the question and uses the correct singular form?"},
"ruby.junior1.snack-preferences": {
"q1": "You want to ask if Eva likes tomatoes. Choose the correct question.",
"q4": "Ben enjoys bread but not milk. Which sentence preserves both facts?"},
"ruby.junior2.invitation-replies": {
"q1": "You would like to join an event, but must look after your younger brother on Saturday. Which reply politely declines and gives the reason?",
"q4": "You are sure you are free and want to accept the invitation 'Can you come?' Which reply is most suitable?"},
"ruby.junior2.rain-backup": {
"q1": "Rain is a real possibility tomorrow, and your plan is to stay indoors if it rains. Choose the correct conditional sentence.",
"q4": "Read: If the cafe is full, we will meet outside. What does this sentence tell us?"},
"ruby.junior3.rain-plan": {
"tomorrow-rain": "Your plan is to meet at the cafe if there is rain tomorrow. Which sentence is grammatical and preserves the plan?",
"reversed-condition": "You promise to stay when the other person needs help. Which sentence expresses this condition in the correct direction?"},
"ruby.junior3.reusable-cafe": {
"jar-action": "You clean an old glass jar and use it to hold pencils, without processing the glass into new material. Which word accurately describes this?",
"so-result": "Every jar was full, and this led you to use a box. Which sentence is grammatical and keeps this cause-and-effect relationship?"},
"ruby.junior3.visitor-station-rules": {
"bags-rule": "The exhibition rule requires visitors to leave backpacks by the door. Which sentence expresses this correctly? A backpack is a bag carried on your back.",
"ask-helper": "A sign should tell people who need help to ask a volunteer. Which sentence is correct? A volunteer is someone who offers to help."},
"ruby.senior1.booked-weekend": {
"q1": "You have arranged to meet a guide tomorrow. Which sentence is grammatical and uses the present continuous for this future arrangement?",
"q4": "Read: I'm meeting Eva at six tomorrow. In the context of an agreed meeting, what does this mainly express?"},
"ruby.senior1.meeting-place-details": {
"q1": "You are identifying the place you often meet. Which expression is natural and complete?",
"q4": "Complete: This is the cafe ___ I visited yesterday. The verb 'visited' needs an object in its clause. Which word can fill the gap?"},
"ruby.senior2.coast-survey-log": {
"counting-since-dawn": "You began counting birds at dawn and are still counting now. Which sentence correctly uses the present perfect continuous to emphasise this ongoing process?",
"known-not-knowing": "You first met a volunteer three years ago and still know them. Which sentence is natural and grammatical? Here, 'know' describes a state.",},
"ruby.senior2.visitor-board-debate": {
"acknowledge-concern": "A friend worries that electronic screens are expensive to maintain. Which reply acknowledges this concern and suggests trying one screen, without claiming costs are certainly low? 'Maintenance' means keeping something in working order.",
"bounded-conclusion": "One screen was tested for one week at an indoor reception desk, and visitors understood it easily. Which conclusion treats the result as promising without extending it to every outdoor location?"},
"ruby.senior2.volunteer-handover": {
"boxes-before-arrival": "You finished checking all the boxes before everyone arrived at nine yesterday. Which sentence uses the past perfect to emphasise that earlier completion?",
"reversed-history": "You checked a water tank on Monday and discovered a leak on Tuesday. Which sentence preserves this order and uses the past perfect for the earlier check? A tank holds water; a leak lets it escape."},
"ruby.senior3.coastal-display-captions": {
"q1": "Volunteers collected these bottles last week. Which noun phrase correctly describes the bottles and who collected them?",
"q4": "The opening phrase 'Designed for children,' must describe the subject that follows it. Which sentence avoids a dangling modifier?"},
"ruby.senior3.project-conditions": {
"q1": "The indoor workshop will continue whether or not it rains. Which sentence preserves this concessive relationship?",
"q4": "Read: Although the room is small, it is suitable for this group. Which sentence preserves this relationship?"},
}

OPTIONS = {
"cet6.b06": ["It reconsiders the first benefit, suggesting that a reliable connection makes avoiding travel worthless.", "It keeps the first benefit while noting that avoiding travel does not remove the need for a reliable connection.", "It explains the first benefit by saying that the need for a reliable connection removes the need to travel."],
"s1.astra.a16": ["The interview room booking was cancelled, but its recording was kept.", "The interview room booking was kept, but its recording was deleted.", "A different room booking was kept, and material from the original interview room was deleted."],
"s1.astra.a02": ["All pupils, whether or not they need a locker.", "Pupils who have already filled in the form.", "Pupils who need a locker."],
"s1.astra.b06": ["All the photos finished uploading yesterday.", "The upload is still in progress now.", "The speaker plans to start uploading tomorrow."],
"s1.second.c09": ["Taking the speaker's grandmother to a concert.", "Going swimming as usual.", "Buying concert tickets for the speaker's grandmother."],
"s1.astra.b04": ["Gap 1 needs time information; gap 2 needs an object for 'remember'.", "Both gaps need a subject.", "Both gaps must use 'when' simply because they follow 'day'."],
"s1.second.c13": ["Remove 'that' from both sentences.", "Remove 'that' only from sentence 1 and keep it in sentence 2.", "Remove 'that' only from sentence 2 and keep it in sentence 1."],
"s2.astra.r03": ["Sentence 1 uses the address to identify the friends; sentence 2 adds it as extra information about the friends mentioned.", "Both sentences use the address to select some friends; the commas only change the pauses.", "Sentence 1 adds the address as extra information; sentence 2 uses it to identify the friends."],
"s2.astra.b03": ["The speaker has spent some time painting the sign.", "The activity relates to the speaker's present situation.", "Whether the whole sign has been finished."],
"s2.astra.r07": ["Kai has finished the walk; Mei is only considering joining.", "Kai made a decision to join; Mei described enjoying the experience of taking part.", "Kai and Mei both promised to join the same walk next time."],
"s2.astra.r11": ["The friend walked to the library only this morning, not on the other mornings this week.", "The friend walks to the library every morning this week and in every earlier week.", "The friend has walked to the library every morning this week, describing a repeated activity within this week."],
"s2.astra.second.q03": ["The speaker admits causing the damage but denies doing it intentionally.", "The speaker only planned to damage the cover and has not done so yet.", "The speaker admits intentionally damaging the cover, then changing their mind."],
"s2.astra.second.q05": ["The writer has still never watched a film outdoors.", "The writer first watched a film outdoors last Saturday evening.", "The writer had watched films outdoors before last Saturday, but did not do so that evening."],
"s2.astra.second.q10": ["The friend sleeps soundly every night lately, but falls asleep later than before.", "The friend cannot fall asleep at all and stays awake all night.", "The friend has not been sleeping well, but does fall asleep and wakes several times during the night."],
"s3.astra.a03": ["All the boxes contain glass.", "The unmarked boxes definitely contain no glass.", "The marked boxes contain glass; the contents of other boxes are not stated."],
"s3.astra.b06": ["The owner needs to submit the request for someone else to approve.", "The owner has approved the request, which now awaits implementation.", "The request requires the owner's approval; whether approval has been given is not stated."],
"s3.astra.a14": ["Saving the copy was already complete when the speaker was reading the message at nine.", "Reading the message continued from eight until nine.", "All messages had been read before nine."],
"s3.astra.b17": ["The room's availability is unknown, but its size has been confirmed as sufficient.", "The room is known to be available; whether it is large enough remains unknown.", "The room is known to be unavailable and too small."],
"s3.astra.r05": ["Their only purpose in hurrying there was to find out whether the last showing had been cancelled.", "They learnt of the cancellation before hurrying to the cinema.", "After arriving, they unexpectedly discovered that the last showing had been cancelled."],
"cet4.astra.a03": ["Includes the cost of the materials.", "Hides the surface of the materials.", "Introduces only the titles of the materials.", "Refunds the cost of the materials."],
"cet4.astra.b15": ["Cautiously low.", "Already verified as exact.", "Guaranteed not to change.", "Deliberately exaggerated upwards."],
"cet4.astra.a15": ["Temporarily put the simpler design aside after comparing costs.", "Started changing the simpler design after comparing costs.", "Finally chose the simpler design after comparing costs.", "Discussed the simpler design again after comparing costs."],
"cet4.astra.b03": ["Offer an explanation of the claim.", "Provide evidence for the claim.", "Make a prediction about the claim.", "Publish the claim publicly."],
"cet4.astra.b04": ["We added labels only after visitors said the boxes were hard to find.", "After adding labels, we confirmed that visitors found the boxes faster.", "We added labels to help visitors find the correct boxes more easily.", "We added labels only after visitors had found the correct boxes."],
"cet4.astra.b16": ["The form people had to complete.", "The two repeated questions in the form.", "The whole change of shortening the form and removing repeated questions.", "The team responsible for processing the form."],
}

CHARACTER_OPTIONS = {
("marcus.senior3.exhibition-purpose", "q4"): ["It modifies 'person', identifying her as the earliest arrival.", "It says that she became a person in order to arrive.", "It proves that she is arriving right now."],
("marcus.senior3.interview-summary", "q4"): ["It introduces the clause and acts as the object of 'said' within it.", "It only links clauses and has no role within the clause.", "It identifies a person and means the same as 'who'."],
("oliver.senior3.archive-time-viewpoint", "q4"): ["Sorting the papers was in progress at eight yesterday.", "All the papers had been sorted before eight yesterday.", "The papers will be sorted at eight every day in the future."],
("oliver.senior3.repair-report-focus", "q4"): ["The replacement work is in progress.", "All the windows have already been replaced.", "The replacement work will not begin until next year."],
("ruby.junior2.rain-backup", "q4"): ["They will meet outside if the cafe is full.", "The cafe is definitely full already.", "They will meet outside whether or not the cafe is full."],
("ruby.senior1.booked-weekend", "q4"): ["A future meeting that has already been arranged.", "A meeting with Eva definitely happening at the moment of speaking.", "A meeting that happened at six yesterday."],
}
