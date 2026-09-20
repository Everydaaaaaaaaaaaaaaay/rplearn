# Persistent character reading voices — 2026-09-20

## Behavior

CharacterCard now carries optional Codable `readingVoice`, resolved and persisted
on write. Missing legacy values receive a stable assignment; roster startup backfills
existing cards without replacing user data. British male/female characters resolve
to M5/F5. Explicit casting remains stable for other nationalities. Main characters:
Oliver M5, Ruby F3, Marcus M3. Remaining characters use gender/age and deterministic
name-based selection among the available voices. These are bounded casting choices,
not claims that every voice reproduces a character's regional accent.

Manual and queued chat reading, social encounters and realtime calls forward the
same card attribute. User messages and narration share F5 and the narrator identity;
English narration uses en-GB. Dictionary pronunciation retains its dedicated F1.
Apple engine selection/failure fallback remains available: Apple voices are not
Supertonic M/F identifiers, but retain consistent role/gender/locale selection.

F5 is no longer reserved away from characters. Authored Nora/Isla use F5; main
character authored stories retain the same casting as chat. Prepared story clips
whose voice conflicts with current casting are rejected and live synthesis supplies
the correct voice. This avoids silently playing old casting.

Public NPC registration and private content sync accept the validated voice field.
Local export/import carries it; older payloads without it retain an existing value.
No database migration, paid AI assignment or new network generation is involved.

## Verification

- 43 iOS tests: speech routing, seed cards/legacy persistence, story audio integrity,
  automatic reading queue, content synchronization. Result:
  `build/DerivedData/VerificationResults/20260920T070719Z-83233.xcresult`.
- Real ChatViewModel request regression: 1 passed. Result:
  `build/DerivedData/VerificationResults/20260920T070947Z-84791.xcresult`.
- Final speech/story regression after adding stale-casting coverage: 28 passed.
  Result: `build/DerivedData/VerificationResults/20260920T071118Z-85288.xcresult`.
- Backend schema/persona tests: 11 passed; TypeScript and focused ESLint passed.
- iOS architecture check and diff whitespace checks passed.
- Production `20260920-character-voice-v1` activated. Authenticated HTTP validation
  probe accepts the F5 field and rejects F99; deliberately incomplete requests
  created no NPCs. Previous release remains available for rollback.
- `Scripts/preview.sh preview home` installed and launched the latest simulator App.

Phone/TestFlight installs need a new build. No App Store/TestFlight publication was
performed. Voice identity/routing was tested; this does not constitute a listening
review of every possible generated character.
