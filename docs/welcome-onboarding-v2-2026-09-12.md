# Welcome / opening v2 · user corrections, 2026-09-12

## Corrections

The user rejected the welcome screenshot treatment and the tutorial-like opening. The previous
v1 test results did not cover the reported bilingual line breaks or post-layout autoscroll.

- Restore the former SwiftUI concept illustrations, retaining the new welcome backdrop,
  typography and compact footer. Remove the eight rejected screenshot assets from the app
  (2,231,831 bytes). Preview accessibility labels now explicitly call them concepts.
- Remove the story's Continue button. Tap ordinary content/background to advance; choice buttons
  and English word lookup retain their own actions. The completion tap enters character selection
  in onboarding and closes the read-only introduction in replay.
- Tell one coherent group conversation about who will welcome the newcomer to their city.
  Oliver's dry humor leads into Ruby's coffee/turtle enthusiasm and Marcus's street-photography
  invitation, with replies to each other rather than unrelated monologues. Gugu is excitable and
  curious, Gaga is affectionately prickly. Their 咕/嘎 endings are present throughout.
- One three-option interaction changes the ensuing character conversation; all three starters
  remain selectable afterward. Remove language practice, conversation advice and feature teaching.
  Each route has 11 dialogue lines, plus the user's selected response.
- Render English and Chinese as separate vertical views. Only the English paragraph enters
  TappableText; Chinese translation gets secondary typography and explicit spacing.
- Use eager rows for this short local story and scroll to a bottom sentinel after content geometry
  changes. The scroll view also anchors size changes to the bottom, including the choice footer.
- Replace the dense introduction cards with a compact portrait/name/city heading, separated
  occupation, and one character-specific summary. No duplicate flags or hobby-chip wall.

No AI requests or changes to saved conversations, friendship, selected city or learning profile.
The OpenRouter source/test changes remain unrelated and are excluded from this task's commit.

## Verification

- Hosted `OnboardingStoryTests`: passed (all three routes), result
  `20260912T005236Z-56515.xcresult`.
- iPhone 17 Pro UI suite: nine cases passed initially; intro-card lookup initially failed
  because the card lacked an accessibility container. Added `.accessibilityElement(children: .contain)`.
  The strengthened focused rerun passed, checking each new card is on screen and a word popup
  opens without adding the next dialogue line: `20260912T005545Z-57779.xcresult`.
- iPhone SE (3rd generation): three focused cases passed (complete opening/selection,
  autoscroll plus word lookup, all four welcome pages in light/dark), result
  `20260912T005636Z-58170.xcresult`.
- Inspected exported welcome and bilingual/card screenshots at both sizes. Chinese wraps as
  a normal paragraph; new cards reach the bottom without manual scrolling.
- Signed physical-device build passed. LAN installation attempted on the paired iPhone 13;
  CoreDevice returned error 4000, peer no longer reachable. Installation awaits reconnection.

Local result bundles are under `/tmp/lingotrip-grammar-derived-20260911/VerificationResults/`.
Exported screenshots are under `/tmp/opening-v2-focused-images` and `/tmp/opening-v2-small-images`.
