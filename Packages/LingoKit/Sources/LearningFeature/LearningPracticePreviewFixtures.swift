#if DEBUG
import Foundation

// Existing original high-school materials, isolated from the release bundle and live grading.
enum PracticePreviewFixtures {
    static let tasks: [PracticePreviewTask] = {
        let source = #"""
[
  {
    "id": "reading",
    "label": "阅读理解",
    "headline": "两篇阅读",
    "detail": "一个星空之夜，一本意外的礼物。",
    "minutes": 18,
    "sections": [
      {
        "id": "preview.138.0",
        "kind": "reading",
        "title": "A first evening of astronomy",
        "text": "The North Hill Learning Centre offers an introductory astronomy evening on Saturday, 24 October, for students aged fifteen to eighteen. No knowledge of astronomy is required. Staff will begin indoors with a short explanation of the evening sky, then use the courtyard for observation if conditions allow.\n\nArrive at 18:15 for registration. The indoor session starts at 18:30, and the programme ends at 21:00. Participants must remain with staff during the outdoor part. The centre supplies the equipment used in the session; personal telescopes are not needed and cannot be set up without agreement.\n\nThe fee is fourteen pounds. Book online by Wednesday, choosing one place for each participant. A request is confirmed only after the centre replies. Students under eighteen need parental or guardian consent; eighteen-year-olds complete their own form. Everyone provides an emergency contact.\n\nWear warm layers and suitable shoes. The courtyard may be colder than expected after the indoor talk. A hot drink is included, but participants should bring any personal water bottle they need. Food is not provided as a full evening meal.\n\nCloud does not automatically cancel the event. Staff may use prepared sky images and demonstrations indoors instead. The session introduces observation and interpretation, without guaranteeing a view of a particular object. If the centre itself cancels, confirmed participants receive a refund or another date. Contact staff before booking about access requirements.",
        "instruction": "Read the passage and choose the best answer.",
        "questions": [
          {
            "id": "preview.138.0.q1",
            "prompt": "What should a beginner understand about the equipment?",
            "options": [
              {
                "id": "A",
                "text": "Every participant must bring a telescope"
              },
              {
                "id": "B",
                "text": "Equipment is available only to experts"
              },
              {
                "id": "C",
                "text": "The centre supplies it"
              },
              {
                "id": "D",
                "text": "Personal telescopes can be set up anywhere"
              }
            ],
            "correctOption": "C",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Centre provides required equipment, personal setups need agreement. Other claims contradict access for beginners.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.138.0.q2",
            "prompt": "When does registration begin for participants?",
            "options": [
              {
                "id": "A",
                "text": "21:00"
              },
              {
                "id": "B",
                "text": "Wednesday midnight"
              },
              {
                "id": "C",
                "text": "18:15"
              },
              {
                "id": "D",
                "text": "18:30"
              }
            ],
            "correctOption": "C",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "18:15 arrival registration,18:30session,21end,Wednesdaybooking deadline.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.138.0.q3",
            "prompt": "What may happen on a cloudy evening?",
            "options": [
              {
                "id": "A",
                "text": "Every participant receives a meal instead"
              },
              {
                "id": "B",
                "text": "An indoor alternative is used"
              },
              {
                "id": "C",
                "text": "A particular star view is guaranteed"
              },
              {
                "id": "D",
                "text": "The event is always cancelled automatically"
              }
            ],
            "correctOption": "B",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Prepared images/demonstrations can replace observation. No automatic cancellation/view/meal promise.",
            "evidenceParagraph": 4
          }
        ]
      },
      {
        "id": "preview.138.1",
        "kind": "reading",
        "title": "The book I had not asked for",
        "text": "For my birthday, my aunt gave me a collection of travel writing. I had asked for a novel by my favourite author, and the unfamiliar book felt like evidence that she had not listened. I thanked her politely and put it beneath two books I already knew I wanted to read.\n\nA few weeks later, I needed something to read on a long journey. The novel was too large for my small bag, so I picked up my aunt's gift. I expected to read a few pages and fall asleep. Instead, I found an account of a town I had visited with my family.\n\nThe writer noticed things I remembered but had never put into words: the sound of shutters opening, the narrowness of a particular street, the way people waited outside a bakery. I did not agree with every judgement, but the familiar place made me curious about the next essay.\n\nBy the time I reached my destination, I had read half the book. I called my aunt to ask how she had chosen it. She said I often told detailed stories about places after trips. She had thought I might enjoy seeing how another person did something similar.\n\nHer choice had not been random, although it had differed from my request. That did not mean every unexpected present was automatically perfect. It meant I had judged this one before discovering the attention behind it.\n\nI finished the collection and lent it to a friend, then bought the novel I originally wanted with birthday money. There was room for both. My aunt's gift had not replaced my preference; it had added another possibility. Now, when I see its worn cover on the shelf, I remember the journey and the small surprise of discovering that someone had noticed a part of my interests I had not named myself.",
        "instruction": "Read the passage and choose the best answer.",
        "questions": [
          {
            "id": "preview.138.1.q1",
            "prompt": "Why is the narrator initially disappointed?",
            "options": [
              {
                "id": "A",
                "text": "The narrator has already read the collection"
              },
              {
                "id": "B",
                "text": "The book contains no writing"
              },
              {
                "id": "C",
                "text": "The aunt gives no present"
              },
              {
                "id": "D",
                "text": "The gift differs from the requested novel"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Expected favourite-author novel, received unfamiliar travel essays. Other reasons not stated.",
            "evidenceParagraph": 0
          },
          {
            "id": "preview.138.1.q2",
            "prompt": "What first engages the narrator during the journey?",
            "options": [
              {
                "id": "A",
                "text": "A letter written by the aunt on every page"
              },
              {
                "id": "B",
                "text": "A blank page for sleeping"
              },
              {
                "id": "C",
                "text": "An essay about a familiar town"
              },
              {
                "id": "D",
                "text": "A guaranteed prize inside the book"
              }
            ],
            "correctOption": "C",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Familiar town and observed details draw interest. Other objects/promises absent.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.138.1.q3",
            "prompt": "How had the aunt chosen the book?",
            "options": [
              {
                "id": "A",
                "text": "She noticed the narrator’s detailed stories about trips"
              },
              {
                "id": "B",
                "text": "She believed every reader likes identical books"
              },
              {
                "id": "C",
                "text": "She wanted the narrator to stop reading novels"
              },
              {
                "id": "D",
                "text": "She selected the cheapest cover without thought"
              }
            ],
            "correctOption": "A",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Aunt links existing travel storytelling interest. Other motives unsupported.",
            "evidenceParagraph": 3
          },
          {
            "id": "preview.138.1.q4",
            "prompt": "What does the ending suggest?",
            "options": [
              {
                "id": "A",
                "text": "Unexpected gifts must always replace chosen interests"
              },
              {
                "id": "B",
                "text": "Attention can be judged only by exact requests"
              },
              {
                "id": "C",
                "text": "The original novel becomes forbidden"
              },
              {
                "id": "D",
                "text": "A new possibility can accompany an existing preference"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Narrator enjoys both gift and wanted novel. Other absolute replacements contradict.",
            "evidenceParagraph": 5
          }
        ]
      }
    ]
  },
  {
    "id": "cloze",
    "label": "完形填空",
    "headline": "一篇完整完形",
    "detail": "在完整的故事里，找到恰当的表达。",
    "minutes": 20,
    "sections": [
      {
        "id": "preview.150.0",
        "kind": "cloze",
        "title": "The score I nearly announced",
        "text": "At a school basketball afternoon, I helped announce the scores. I enjoyed the microphone and wanted every result to sound ____1____. During a close game, one team scored just as the final signal sounded. Several spectators cheered, and I prepared to announce their ____2____. The teacher beside me raised a hand. The officials were still discussing whether the shot had been made in ____3____. My excitement had moved faster than the decision. I needed to wait for the ____4____ result, not choose the version supported by the loudest ____5____.\n\nThe pause felt long. Someone called out for me to get on with it. I explained briefly that confirmation was still needed. The microphone could carry useful information, but it could also spread an unconfirmed ____6____ to the whole hall. A minute later, the officials gave the score. The late shot did not count. I read the confirmed numbers without adding my own ____7____. One team was disappointed, yet its players knew the decision had come from the officials rather than the person with the ____8____. Afterwards, the teacher thanked me for keeping the roles ____9____. I had not judged the play; I had communicated the judgement when it was ____10____.\n\nFor the remaining games, I checked the written result before speaking. This did not make every announcement exciting, but it made the process dependable. At the final match, a player thanked the volunteers who had helped the afternoon run smoothly. I was one small part of that group. The useful skill had not been sounding certain at every ____11____. It had been knowing when certainty was not yet ____12____. I still liked the microphone, but no longer confused being heard with being the source of every answer. A brief pause could protect everyone from a public ____13____. My job was to make the result clear after checking it, not make the checking ____14____ so I could speak sooner. The best announcement began with the patience to ____15____.",
        "instruction": "Choose the best word or phrase for each blank.",
        "questions": [
          {
            "id": "preview.150.0.q1",
            "prompt": "Choose the best word or phrase for blank 1.",
            "options": [
              {
                "id": "A",
                "text": "distant"
              },
              {
                "id": "B",
                "text": "confident"
              },
              {
                "id": "C",
                "text": "secret"
              },
              {
                "id": "D",
                "text": "uninterested"
              }
            ],
            "correctOption": "B",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The narrator wants assured announcements.",
            "evidenceParagraph": 0
          },
          {
            "id": "preview.150.0.q2",
            "prompt": "Choose the best word or phrase for blank 2.",
            "options": [
              {
                "id": "A",
                "text": "victory"
              },
              {
                "id": "B",
                "text": "practice"
              },
              {
                "id": "C",
                "text": "absence"
              },
              {
                "id": "D",
                "text": "departure"
              }
            ],
            "correctOption": "A",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The apparent last score could win the close game.",
            "evidenceParagraph": 0
          },
          {
            "id": "preview.150.0.q3",
            "prompt": "Choose the best word or phrase for blank 3.",
            "options": [
              {
                "id": "A",
                "text": "ink"
              },
              {
                "id": "B",
                "text": "advance of the game"
              },
              {
                "id": "C",
                "text": "silence"
              },
              {
                "id": "D",
                "text": "time"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Officials determine whether the shot preceded the final signal.",
            "evidenceParagraph": 0
          },
          {
            "id": "preview.150.0.q4",
            "prompt": "Choose the best word or phrase for blank 4.",
            "options": [
              {
                "id": "A",
                "text": "official"
              },
              {
                "id": "B",
                "text": "most cheerful"
              },
              {
                "id": "C",
                "text": "quickest guess"
              },
              {
                "id": "D",
                "text": "loudest"
              }
            ],
            "correctOption": "A",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The authorised decision must be confirmed.",
            "evidenceParagraph": 0
          },
          {
            "id": "preview.150.0.q5",
            "prompt": "Choose the best word or phrase for blank 5.",
            "options": [
              {
                "id": "A",
                "text": "written numbers"
              },
              {
                "id": "B",
                "text": "cheers"
              },
              {
                "id": "C",
                "text": "instructions"
              },
              {
                "id": "D",
                "text": "whistles from officials"
              }
            ],
            "correctOption": "B",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Crowd enthusiasm is not the official result.",
            "evidenceParagraph": 0
          },
          {
            "id": "preview.150.0.q6",
            "prompt": "Choose the best word or phrase for blank 6.",
            "options": [
              {
                "id": "A",
                "text": "ball"
              },
              {
                "id": "B",
                "text": "claim"
              },
              {
                "id": "C",
                "text": "microphone"
              },
              {
                "id": "D",
                "text": "player"
              }
            ],
            "correctOption": "B",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Premature speech would broadcast an unverified claim.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.150.0.q7",
            "prompt": "Choose the best word or phrase for blank 7.",
            "options": [
              {
                "id": "A",
                "text": "confirmation"
              },
              {
                "id": "B",
                "text": "numbers"
              },
              {
                "id": "C",
                "text": "announcement"
              },
              {
                "id": "D",
                "text": "opinion"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The announcer reads rather than adds a personal view.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.150.0.q8",
            "prompt": "Choose the best word or phrase for blank 8.",
            "options": [
              {
                "id": "A",
                "text": "ball at the final shot"
              },
              {
                "id": "B",
                "text": "whistle as referee"
              },
              {
                "id": "C",
                "text": "team uniform"
              },
              {
                "id": "D",
                "text": "microphone"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The narrator has the microphone but does not officiate.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.150.0.q9",
            "prompt": "Choose the best word or phrase for blank 9.",
            "options": [
              {
                "id": "A",
                "text": "secret"
              },
              {
                "id": "B",
                "text": "unnecessary"
              },
              {
                "id": "C",
                "text": "separate"
              },
              {
                "id": "D",
                "text": "identical"
              }
            ],
            "correctOption": "C",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Communication and judgement are distinct roles.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.150.0.q10",
            "prompt": "Choose the best word or phrase for blank 10.",
            "options": [
              {
                "id": "A",
                "text": "ready"
              },
              {
                "id": "B",
                "text": "forgotten"
              },
              {
                "id": "C",
                "text": "popular"
              },
              {
                "id": "D",
                "text": "exciting"
              }
            ],
            "correctOption": "A",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The result is announced once available and confirmed.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.150.0.q11",
            "prompt": "Choose the best word or phrase for blank 11.",
            "options": [
              {
                "id": "A",
                "text": "stadium"
              },
              {
                "id": "B",
                "text": "future career"
              },
              {
                "id": "C",
                "text": "volume"
              },
              {
                "id": "D",
                "text": "moment"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The lesson concerns resisting constant apparent certainty.",
            "evidenceParagraph": 2
          },
          {
            "id": "preview.150.0.q12",
            "prompt": "Choose the best word or phrase for blank 12.",
            "options": [
              {
                "id": "A",
                "text": "popular"
              },
              {
                "id": "B",
                "text": "justified"
              },
              {
                "id": "C",
                "text": "possible to imitate"
              },
              {
                "id": "D",
                "text": "audible"
              }
            ],
            "correctOption": "B",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Certainty requires adequate confirmation.",
            "evidenceParagraph": 2
          },
          {
            "id": "preview.150.0.q13",
            "prompt": "Choose the best word or phrase for blank 13.",
            "options": [
              {
                "id": "A",
                "text": "farewell"
              },
              {
                "id": "B",
                "text": "victory"
              },
              {
                "id": "C",
                "text": "practice"
              },
              {
                "id": "D",
                "text": "correction"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Waiting avoids a publicly incorrect announcement needing correction.",
            "evidenceParagraph": 2
          },
          {
            "id": "preview.150.0.q14",
            "prompt": "Choose the best word or phrase for blank 14.",
            "options": [
              {
                "id": "A",
                "text": "more thorough"
              },
              {
                "id": "B",
                "text": "slower on purpose"
              },
              {
                "id": "C",
                "text": "clearer"
              },
              {
                "id": "D",
                "text": "disappear"
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The checking should not be removed to accelerate speaking.",
            "evidenceParagraph": 2
          },
          {
            "id": "preview.150.0.q15",
            "prompt": "Choose the best word or phrase for blank 15.",
            "options": [
              {
                "id": "A",
                "text": "interrupt"
              },
              {
                "id": "B",
                "text": "wait"
              },
              {
                "id": "C",
                "text": "guess"
              },
              {
                "id": "D",
                "text": "cheer first"
              }
            ],
            "correctOption": "B",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Patient confirmation precedes the announcement.",
            "evidenceParagraph": 2
          }
        ]
      }
    ]
  },
  {
    "id": "insertion-grammar",
    "label": "七选五 · 语法",
    "headline": "两组语篇填空",
    "detail": "先选句子，再在另一篇文章中填写词语。",
    "minutes": 20,
    "sections": [
      {
        "id": "preview.152.0",
        "kind": "insertion",
        "title": "Packing for a day out",
        "text": "Packing for a day out can be easier when you think through the actual journey rather than collect everything you might possibly want. A useful bag supports the plan without becoming a burden.\n\nBegin with the essential requirements. Tickets, agreed supplies and any instructions from the organiser should come before extra entertainment. ____1____ This prevents a full bag from hiding the one item you truly need.\n\nCheck how long you will carry the bag. A comfortable load at home may feel different after a long walk. ____2____ The journey matters as much as the destination.\n\nPut things where you can reach them when needed. A ticket buried beneath lunch creates unnecessary searching at the entrance. ____3____ Small decisions about order can save repeated unpacking.\n\nKeep appropriate items separate. A wet coat and dry paper should not share the same unprotected space. ____4____ Follow any specific storage guidance for food or equipment.\n\nFinally, review the bag once it is packed. ____5____ Removing an unnecessary item can be more useful than finding another pocket. The aim is to carry what the day requires while leaving enough attention and energy to enjoy it.",
        "instruction": "Choose the best sentence for each gap. Two sentences are not needed.",
        "questions": [
          {
            "id": "preview.152.0.q1",
            "prompt": "Choose the sentence for gap 1.",
            "options": [
              {
                "id": "A",
                "text": "Make a short list of essentials before choosing optional extras."
              },
              {
                "id": "B",
                "text": "Ask whether every object has a clear role in the plan."
              },
              {
                "id": "C",
                "text": "Consider the distance and available help before adding more weight."
              },
              {
                "id": "D",
                "text": "Suitable separation can protect one item from another."
              },
              {
                "id": "E",
                "text": "Some bags are displayed in shop windows beside shoes."
              },
              {
                "id": "F",
                "text": "Place the next item you will use in an accessible compartment."
              },
              {
                "id": "G",
                "text": "Many travellers keep photographs after returning from a holiday."
              }
            ],
            "correctOption": "A",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The essential list establishes priorities before optional items.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.152.0.q2",
            "prompt": "Choose the sentence for gap 2.",
            "options": [
              {
                "id": "A",
                "text": "Make a short list of essentials before choosing optional extras."
              },
              {
                "id": "B",
                "text": "Ask whether every object has a clear role in the plan."
              },
              {
                "id": "C",
                "text": "Consider the distance and available help before adding more weight."
              },
              {
                "id": "D",
                "text": "Suitable separation can protect one item from another."
              },
              {
                "id": "E",
                "text": "Some bags are displayed in shop windows beside shoes."
              },
              {
                "id": "F",
                "text": "Place the next item you will use in an accessible compartment."
              },
              {
                "id": "G",
                "text": "Many travellers keep photographs after returning from a holiday."
              }
            ],
            "correctOption": "C",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Distance and support determine a realistic carrying load.",
            "evidenceParagraph": 2
          },
          {
            "id": "preview.152.0.q3",
            "prompt": "Choose the sentence for gap 3.",
            "options": [
              {
                "id": "A",
                "text": "Make a short list of essentials before choosing optional extras."
              },
              {
                "id": "B",
                "text": "Ask whether every object has a clear role in the plan."
              },
              {
                "id": "C",
                "text": "Consider the distance and available help before adding more weight."
              },
              {
                "id": "D",
                "text": "Suitable separation can protect one item from another."
              },
              {
                "id": "E",
                "text": "Some bags are displayed in shop windows beside shoes."
              },
              {
                "id": "F",
                "text": "Place the next item you will use in an accessible compartment."
              },
              {
                "id": "G",
                "text": "Many travellers keep photographs after returning from a holiday."
              }
            ],
            "correctOption": "F",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The accessible compartment addresses finding the ticket quickly.",
            "evidenceParagraph": 3
          },
          {
            "id": "preview.152.0.q4",
            "prompt": "Choose the sentence for gap 4.",
            "options": [
              {
                "id": "A",
                "text": "Make a short list of essentials before choosing optional extras."
              },
              {
                "id": "B",
                "text": "Ask whether every object has a clear role in the plan."
              },
              {
                "id": "C",
                "text": "Consider the distance and available help before adding more weight."
              },
              {
                "id": "D",
                "text": "Suitable separation can protect one item from another."
              },
              {
                "id": "E",
                "text": "Some bags are displayed in shop windows beside shoes."
              },
              {
                "id": "F",
                "text": "Place the next item you will use in an accessible compartment."
              },
              {
                "id": "G",
                "text": "Many travellers keep photographs after returning from a holiday."
              }
            ],
            "correctOption": "D",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "Separation prevents moisture damaging dry items.",
            "evidenceParagraph": 4
          },
          {
            "id": "preview.152.0.q5",
            "prompt": "Choose the sentence for gap 5.",
            "options": [
              {
                "id": "A",
                "text": "Make a short list of essentials before choosing optional extras."
              },
              {
                "id": "B",
                "text": "Ask whether every object has a clear role in the plan."
              },
              {
                "id": "C",
                "text": "Consider the distance and available help before adding more weight."
              },
              {
                "id": "D",
                "text": "Suitable separation can protect one item from another."
              },
              {
                "id": "E",
                "text": "Some bags are displayed in shop windows beside shoes."
              },
              {
                "id": "F",
                "text": "Place the next item you will use in an accessible compartment."
              },
              {
                "id": "G",
                "text": "Many travellers keep photographs after returning from a holiday."
              }
            ],
            "correctOption": "B",
            "acceptedAnswers": [],
            "rejectedAnswers": [],
            "explanation": "The final review tests whether each object is needed.",
            "evidenceParagraph": 5
          }
        ]
      },
      {
        "id": "preview.152.1",
        "kind": "grammar",
        "title": "Printing a class poster",
        "text": "Our class designed a poster for a reading afternoon. The teacher ____1____ (bring) a sample print so we could compare the page on a screen with one on paper. The two did not look exactly alike.\n\nSeveral ____2____ (design) used a dark background. It made the title dramatic as well ____3____ easy to notice, but some small words became difficult to read. We needed to check the details, not only admire the first impression.\n\nI looked at ____4____ (I) draft from the back of the room. A pale line had almost disappeared. The teacher asked me ____5____ (change) its colour before making another sample.\n\nThere was room ____6____ a short date line beneath the title. We made sure the date and place were not separated by a decorative picture. Someone looking quickly should be able to find both.\n\nThe second version was ____7____ (clear) than the first. We checked the spelling ____8____ (careful), comparing the words with the approved event details. Each poster ____9____ (check) before it was put on a noticeboard.\n\nThe finished design still used colour and pictures, but its practical information no longer depended on a viewer coming very close. We had tested it in a place like the one where people would see it. That was ____10____ useful step between making an attractive page and making a message that worked for its readers.",
        "instruction": "Fill each gap with one appropriate word or the correct form of the word in brackets.",
        "questions": [
          {
            "id": "preview.152.1.q1",
            "prompt": "Fill gap 1 with the correct form of bring.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "brought",
              "had brought"
            ],
            "rejectedAnswers": [
              "bringing"
            ],
            "explanation": "The past account requires a finite past form, not an unaided -ing form.",
            "evidenceParagraph": 0
          },
          {
            "id": "preview.152.1.q2",
            "prompt": "Fill gap 2 with the correct form of design.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "designs"
            ],
            "rejectedAnswers": [
              "design"
            ],
            "explanation": "The plural quantifier requires the plural noun.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.152.1.q3",
            "prompt": "Fill gap 3 with one appropriate word.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "as"
            ],
            "rejectedAnswers": [
              "than"
            ],
            "explanation": "As well as is the additive construction.",
            "evidenceParagraph": 1
          },
          {
            "id": "preview.152.1.q4",
            "prompt": "Fill gap 4 with the correct form of I.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "my"
            ],
            "rejectedAnswers": [
              "I"
            ],
            "explanation": "A possessive determiner is required before the noun.",
            "evidenceParagraph": 2
          },
          {
            "id": "preview.152.1.q5",
            "prompt": "Fill gap 5 with the correct form of change.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "to change"
            ],
            "rejectedAnswers": [
              "changeing"
            ],
            "explanation": "The preceding verb plus object takes a to-infinitive.",
            "evidenceParagraph": 2
          },
          {
            "id": "preview.152.1.q6",
            "prompt": "Fill gap 6 with one appropriate word.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "for"
            ],
            "rejectedAnswers": [
              "during"
            ],
            "explanation": "Room for introduces the purpose of the available space.",
            "evidenceParagraph": 3
          },
          {
            "id": "preview.152.1.q7",
            "prompt": "Fill gap 7 with the correct form of clear.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "clearer"
            ],
            "rejectedAnswers": [],
            "explanation": "The comparison with than requires a comparative form; other unlisted variants remain reviewable.",
            "evidenceParagraph": 4
          },
          {
            "id": "preview.152.1.q8",
            "prompt": "Fill gap 8 with the correct form of careful.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "carefully"
            ],
            "rejectedAnswers": [],
            "explanation": "The action requires the adverbial form; unlisted grammatical variants remain reviewable.",
            "evidenceParagraph": 4
          },
          {
            "id": "preview.152.1.q9",
            "prompt": "Fill gap 9 with the correct form of check.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "was checked",
              "had been checked"
            ],
            "rejectedAnswers": [],
            "explanation": "Each singular object receives the action, requiring singular passive; unlisted alternatives remain reviewable.",
            "evidenceParagraph": 4
          },
          {
            "id": "preview.152.1.q10",
            "prompt": "Fill gap 10 with one appropriate word.",
            "options": [],
            "correctOption": null,
            "acceptedAnswers": [
              "a"
            ],
            "rejectedAnswers": [
              "an"
            ],
            "explanation": "The article follows the initial sound of the next adjective.",
            "evidenceParagraph": 5
          }
        ]
      }
    ]
  }
]
"""#
        // A malformed developer fixture is a build-time authoring mistake, never a server fallback.
        return try! JSONDecoder().decode([PracticePreviewTask].self, from: Data(source.utf8))
    }()
}
#endif
