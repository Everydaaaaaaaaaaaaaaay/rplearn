# Composer viewport following — 2026-09-21

The translator mode change previously scrolled before the larger composer completed layout. A later viewport shrink could obscure the latest message and incorrectly clear the near-bottom state.

The message list now observes its effective viewport (container size minus safe-area content insets) and follows the bottom anchor as it changes. Bottom-follow intent is separate from transient proximity and changes with intentional user scrolling, history highlighting, sending, input focus, and the return-to-bottom button. Reading older messages does not force a jump merely because the panel resizes.

The focused composer UI regression now checks the latest message row's actual frame against the expanded panel, both after opening and after entering Chinese with the keyboard. Existing draft preservation and repeated toggle checks remain. A stable row accessibility identifier is used because the tappable message text is not a single static-text element.

Verification: focused UI test passed (1 passed, 0 failed), `build/DerivedData/VerificationResults/20260921T121923Z-74192.xcresult`. Expanded-panel screenshot inspected; latest bubble is fully visible above the composer with keyboard present. Architecture and whitespace checks passed. Latest Debug build installed with `Scripts/preview.sh preview contacts`.
