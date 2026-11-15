# BetterBoard — Plan (v1)

An iOS keyboard that looks like Apple's default keyboard, with Gboard-style
**hold-for-symbols**: each letter key shows a small symbol in its top-right
corner; holding the key swaps to that symbol, releasing types it.

Goal for v1: **simple, small, just works.** Advanced options come later.

## Target
- iPhone 17 Pro Max, iOS 27.2.1 (portrait first, landscape scales proportionally)
- Minimum deployment target: iOS 17.0 (so any recent Xcode on the build machine works)
- Visual style: match Apple's iOS 27 keyboard (light + dark), from user screenshots

## Build & install (no Mac — everything from Windows, all free)
1. Code is written on Windows in this folder.
2. Pushed to a **public** GitHub repo.
3. **GitHub Actions** (macOS runner, latest stable Xcode) runs XcodeGen, builds
   unsigned for `iphoneos`, packages `BetterBoard.ipa`, uploads it as an artifact.
4. `scripts/get-ipa.ps1` downloads the latest `.ipa` into `build/` via `gh`.
5. User installs with **Sideloadly** (free Apple ID; re-sign every 7 days).

Windows needs: Git, GitHub CLI (`gh`), Sideloadly, iTunes + iCloud (Apple
website versions, not Microsoft Store).

Free Apple ID limits: 7-day expiry, max 3 sideloaded apps, 10 App IDs/week
→ keep bundle IDs fixed once chosen.

## Dependencies
- **No third-party code.** Apple frameworks only: UIKit (keyboard), SwiftUI
  (container app), `UITextChecker` (spelling/autocorrect), `UILexicon`
  (text replacements).
- Build tooling: XcodeGen (installed in CI), GitHub Actions.
- No local Swift compile on Windows — CI is the compiler.

## Architecture decisions
1. **Two targets:** container app (setup instructions + test text field) and
   keyboard extension (all the logic).
2. **No Full Access** (`RequestsOpenAccess = false`). No privacy warning.
   Consequence: no haptics / key click sounds in v1.
3. **Settings live inside the keyboard** (⚙ in the suggestion bar opens a
   settings panel in place of the keys). Stored in the extension's own
   `UserDefaults` → no App Groups, no Full Access, works with a free Apple ID.
4. **One custom `KeyboardView`** draws keys and handles raw touches
   (no UIButtons / gesture recognisers). Gaps between keys hit the nearest key.
5. **Key press state machine:**
   - Touch down → popup shows letter, start hold timer.
   - Timer fires (default **300 ms**, Gboard's default) → popup shows symbol.
   - Touch up → type whatever the popup shows.
   - Slide before timer → follow finger to new key.
   - New touch while one is held → commit the held key immediately (fast typing).
6. **Special keys:** shift (tap = one capital, double-tap = caps lock),
   backspace (repeat on hold, word-delete after ~2 s), return (label follows
   `returnKeyType`), 123 / #+= pages (`£ € ¥` on #+=).
   - **Emoji key** → `advanceToNextInputMode()`; user sets keyboards to
     BetterBoard + Emoji so it jumps straight to Apple's emoji keyboard.
   - Globe/mic are drawn by iOS below the keyboard on Face ID iPhones, so the
     bottom row is **123 · emoji · space · return**.
7. **Suggestion bar** above the keys: [⚙] typed word · best correction ·
   completion. Also gives the top-row popups room to draw (extensions can't
   draw above their own bounds).
8. **Autocorrect:** `UITextChecker` with `en_AU` (fallback `en_GB`).
   On space/punctuation, replace a misspelled word with a close guess
   (edit distance ≤ 2). Backspace right after a correction reverts it and
   learns the word. `UILexicon` words never get corrected.
   Also: auto-capitalisation, double-space → ". ".
9. **Theme** in one file (sizes, radii, colours, fonts); light/dark follows
   the host app. Symbol hints: small grey, top-right of each key.

## Symbol map (US `$` on D)
```
Q% W\ E| R= T[ Y] U< I> O{ P}
 A@ S# D$ F_ G& H- J+ K( L)
    Z* X" C' V: B; N! M?
```

## Settings (v1)
| Group  | Setting                              | Default |
|--------|--------------------------------------|---------|
| Keys   | Hold for symbols                     | On      |
|        | Long-press delay (100–1000 ms)       | 300 ms  |
|        | Show symbol hints                    | On      |
|        | Popup on key press                   | On      |
|        | Number row                           | Off     |
|        | Keyboard height (Short/Normal/Tall)  | Normal  |
| Typing | Auto-correction                      | On      |
|        | Auto-capitalisation                  | On      |
|        | Double-space full stop               | On      |
|        | Double-tap Shift for caps lock       | On      |
| Other  | Reset learned words                  | —       |

## Out of scope for v1
Swipe typing, accents popup, spacebar cursor trackpad, haptics/sounds
(need Full Access), themes, multiple languages.

## Project layout
```
BetterBoard/
  project.yml                     XcodeGen config
  .github/workflows/build.yml     CI → BetterBoard.ipa
  App/BetterBoardApp.swift        setup screen + test field
  Keyboard/
    KeyboardViewController.swift  entry point, text insertion
    KeyboardView.swift            key drawing, touches, hold timer
    KeyPopup.swift                popup balloon
    Layout.swift                  rows, symbol map, 123/#+= pages
    Theme.swift                   sizes, colours, light/dark
    Autocorrect.swift             UITextChecker + suggestion logic
    Settings.swift                settings model + in-keyboard panel
    Info.plist                    extension config (Full Access off)
  scripts/get-ipa.ps1             download latest .ipa to build/
```

## Build order
1. Skeleton: letters, space, backspace, return, emoji key — installed and typing.
2. Apple look: sizes, colours, popup, dark mode.
3. Hold-for-symbols: hints, hold swap, multi-touch.
4. 123 / #+= pages.
5. Autocorrect + suggestion bar.
6. Settings panel.
7. Polish: caps lock, double-space, backspace repeat.

## Still needed from user
- Screenshots of Apple's keyboard on iOS 27 (light + dark)
- GitHub account
