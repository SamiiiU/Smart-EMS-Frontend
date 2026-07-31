# Handoff — Rulings 5.1 / 5.2 + T4 Global states (2026-07-30)

**T5 not started.**

## Part 1 — Rulings 5.1 and 5.2

**RULING 5.1 — glyph letter size (D-37)**
- `sizing.dart` — `statusGlyphMd` 16 → **22**, new `statusGlyphLetterMd` **13**
  (an explicit size, not the old ratio). `statusGlyphSm` stays 12 and now
  carries **shape only**; `statusGlyphLetterRatio` is gone.
- `status_pill.dart` — a letterless pill is **unrepresentable**: the
  constructor asserts `showLabel || (md && attendance)`, written as a
  const-evaluable disjunction so const call sites fail at **compile time**,
  not just in debug. `letterFitsAt(size)` exposes the rule.
- The sub-floor pin test is deleted (it did its job) and replaced with four
  D-37 tests, including that a small pill shows the WORD and that both
  letterless combinations throw.
- Gallery updated: at `sm` it now renders the words plus a note that
  `showLabel: false` is unrepresentable there.

**RULING 5.2 — inverting filled-glyph letter (D-38)**
- `tokens.dart` — new `onFilledGlyph(statusBg)`: `#FFFFFF` in light, the
  status's own `…Bg` in dark. Required adding a `brightness` field to the
  extension.
- Contrast test rewritten: the known-exception range is gone, and it now
  asserts the ruling's reasoning — that white-in-dark would be **1.91:1**,
  which is why the token inverts rather than being pinned.

**Verified visually** in `primitives_dark.png`: the `sm` row shows words with
shape-only glyphs; `md` glyphs are visibly larger with legible `P` / `A` / `—`
/ `Lv` / `E`.

**One figure correction.** RULING 5.2 gave white-on-`success` as 4.72:1; it
measures **5.07:1**. The conclusion holds with a larger margin. The same
formula reproduces the ruling's other figure (4.45:1) exactly, so 4.72 looks
like the outlier. Asserted at 5.07 with a comment.

## Part 2 — T4 Global states

**`lib/core/widgets/states/`**
- `screen_state.dart` — `ScreenState<T>`, `NetworkStatus`, `LoadFailure`,
  `ScreenOutcome`, `resolveOutcome()`, `adornmentFor()`. The rule, once.
- `screen_state_builder.dart` — `ScreenStateBuilder<T>` + `OfflineBanner`.
- `loading_skeleton.dart` — 4 variants, opacity-only shimmer.
- `empty_state.dart` — `StateFrame`, `EmptyState`, `FilteredEmptyState`.
- `error_state.dart` — `ErrorState`, `OfflineState`, `UnlinkedProfileState`.

**Gallery** — `states_gallery.dart`: all six components, every variant, and
**all ten precedence rows rendered live**, wired into the gallery screen.

**Tests** — `test/states_test.dart`, 54 tests.

## Gate result

- [x] **`flutter analyze`** — PASS. `No issues found! (ran in 5.7s)`
- [x] **`flutter test`** — PASS. `00:34 +161: All tests passed!`
      (105 → 161: +54 T4, +2 D-37/D-38 net)
- [x] **`check_tokens.sh` clean, with a negative test planted and removed** —
      PASS.
  ```
  ### planted ###
  _scratch_negative_test.dart:3: raw Color() constructor -> const Color badColor = Color(0xFFFF0000);
  _scratch_negative_test.dart:3: bare hex literal used as a colour -> ...
  _scratch_negative_test.dart:4: EdgeInsets built from a bare numeric literal -> const EdgeInsets badPad = EdgeInsets.all(13);
  _scratch_negative_test.dart:5: SizedBox sized from a bare numeric literal -> const SizedBox badBox = SizedBox(height: 44);
  check_tokens.sh: 4 violation(s) found.   exit=1

  ### removed ###
  check_tokens.sh: clean.   exit=0
  ```
- [x] **`flutter build web`** — PASS. `√ Built build\web`
- [x] **All six in the gallery, both modes, goldens regenerated** — PASS.
      10 goldens now (`states_light/dark` added).

  **What the states golden shows:** the four skeleton variants as grey block
  placeholders at the real components' dimensions; `EmptyState` twice — with
  an action ("No students yet" + Import students) and without ("No
  notifications", no button at all); `FilteredEmptyState` naming the filter
  and offering Clear filter; `ErrorState` with the backend sentence verbatim
  ("Attendance for this date is locked and cannot be edited.") and a Retry;
  `OfflineState` and `UnlinkedProfileState` both in neutral/informational
  tones with **no button**. Then all ten precedence rows in order — and rows
  2 and 6 visibly keep the three student rows with an adornment above them
  (a neutral "Offline — showing saved data" strip, and an amber "Could not
  refresh" notice), which is D-30 made visible rather than asserted.

- [x] **All ten precedence rows asserted** — PASS. Each row at the resolver,
      plus a totality test over every combination of status × connection ×
      hasData × hasFilter × isEmpty, plus the two ordering tests (7 before 8;
      9 over 5/6).
  ```
  row 1..row 10  (ten tests)
  row 7 is checked BEFORE row 8 (D-14)
  row 9 wins over rows 5 and 6 — notLinked is never an error
  exactly one outcome — the resolver is total
  ```
- [x] **No overflow at 360 / 768 / 1366px** — PASS. Every state plus the
      banner, at all three widths.

### The other named tests

```
D-30  offline WITH cache renders rows, not OfflineState
D-30  a FAILED REFRESH over existing data does not blank the list
D-30  loading over existing data keeps the rows and shows no skeleton
D-30  adornment is only attached when the outcome IS data
skeleton  a skeleton list row is at least listRowMinHeight
D-11  the SECOND consecutive failure renders differently from the first
D-14  EmptyState vs FilteredEmptyState are DISTINCT TYPES
D-19  FilteredEmptyState ALWAYS exposes a clear action
style OfflineState / UnlinkedProfileState use no danger token (both modes)
style ErrorState, by contrast, DOES use danger (both modes)
motion shimmer is ABSENT when disableAnimations is set
motion the shimmer animates opacity only, never layout (D-05)
```

The not-an-error tests assert the *contrast* too: `ErrorState` must use
`danger`, otherwise "Offline uses no danger" would pass trivially on a
component that uses no colour at all.

## Two real bugs found while building T4

1. **A production crash for reduced-motion users.** `_ShimmerState` held its
   `AnimationController` in a `late final` initialiser. Under reduced motion
   nothing ever touches it, so the **first** access is `dispose()` — which
   constructs an `AnimationController` during unmount and performs a
   `TickerMode` ancestor lookup on a deactivated element. That throws
   "Looking up a deactivated widget's ancestor is unsafe", in production as
   well as in tests, for exactly the users who asked for less motion. Now
   created eagerly in `initState`.
2. **A contrast failure caught by the suite added last round.** I used
   `textMuted` for the state icons; it measures **2.39:1** on `surface`,
   below the 3:1 non-text floor — the same value that failed for Overline in
   RULING 2.1. Moved to `textSecondary`. The contrast suite caught it within
   minutes of the component being written, which is the argument for it.

Also worth noting: my first reduced-motion test passed a `MediaQuery` *outside*
`MaterialApp`, which does nothing — `MaterialApp` inserts its own from the
view. Fixed via the `builder:` hook. A test that silently tests nothing is
worse than no test.

## Decisions made

`DECISIONS.md` — D-37 and D-38 (rulings), and a T4 section D-T4-01..07.
Headlines: the rule implemented once; `ScreenState` rather than `AsyncValue`
because `hasValue` is easy to forget and forgetting it silently breaks D-30;
row 9 evaluated first; `isEmpty` explicit rather than inferred; shimmer's
exception to D-29; `ErrorState` owning its own attempt count; state icons on
`textSecondary`.

## Deviations from the prompt

1. **`ScreenState<T>` is a new type, not Riverpod's `AsyncValue`.** The spec
   said "taking the async value"; I introduced a purpose-built type because
   the rule turns on *prior data exists*, and `AsyncValue` hides that in
   `hasValue` on a loading/error state. T6 will need a small adapter from
   `AsyncValue` to `ScreenState` — flagging so it is not a surprise.
2. **`isEmpty` must be supplied by the caller.** There is no general way to
   ask an arbitrary `T` for its row count. A screen that forgets it gets rows
   7/8 silently skipped — the one part of the rule a screen can still get
   wrong. Considered requiring an `int Function(T)` instead; rejected as
   heavier for every caller, but it is the safer alternative if you would
   rather close that hole.
3. **`OfflineBanner` is a seventh public widget**, but not a seventh *state* —
   it is the row-2 adornment, and it sits with the builder rather than being
   independently reachable. Flagging per the scope note.
4. **`StateFrame` is exported rather than private.** All five states compose
   it so they stay visually identical, and `iconColour` is a required
   parameter specifically so a caller cannot give a not-an-error state a
   danger tint by omission.
5. **`AppSizing` gained `stateIconSize` (40) and `statCardSkeletonWidth`
   (140).** Both are fixed sizes and the DoD forbids literals in components.
6. **The states golden pumps 450ms before capturing** so the shimmer is at a
   deterministic point in its cycle; otherwise the golden never matches twice.

## Blocked / needs a human

1. *(carried)* **`flutter build apk --debug` fails** — no JDK, Android
   `cmdline-tools` missing. **Due before T5.**
2. *(carried)* **PostToolUse hook not live** — `check_tokens.sh` run manually
   and passing. **Due before T5.**
3. *(carried)* **Backend `gradlew` has CRLF line endings**, so the app image
   cannot be rebuilt on Windows (`./gradlew: not found`, exit 127). Ali's fix.
   The prebuilt image works; compose defines only `db`; the app needs the
   `SPRING_FLYWAY_URL` overrides recorded in `BACKEND_CONTRACT.md`.
4. *(carried)* **`BACKEND_CONTRACT.md` endpoint list pending seeding.** CORS is
   verified; no endpoint is claimed. T7 auth is bearer-only —
   `Access-Control-Allow-Credentials` is absent.
5. *(carried)* **T8 needs a persistent DB** — the native seam is still
   `NativeDatabase.memory()`.
6. *(carried)* **riverpod_generator / drift_dev cannot co-resolve** — providers
   stay hand-written. Relevant to T5, which needs `keepAlive` providers: they
   will be hand-written `Provider`/`NotifierProvider` declarations.

## Next task readiness

T5 (Shell and navigation) depends on T4 and its dependencies are met. What T4
hands it:

- `ScreenStateBuilder` is what every tab's content will sit inside, and D-30 is
  already enforced there — so **D-30's "returning never interrupts" is half
  done**: skeletons cannot appear over data the user can already see, because
  the rule forbids it. What T5 adds is the keep-alive half (`indexedStack`,
  `AutomaticKeepAliveClientMixin`, per-tab scroll).
- `UnlinkedProfileState` is the `/me` 404 path, which T5's shell will hit
  first, before any tab renders.

Two seeded decisions are directly T5 material and worth reading before
starting: **D-31** (destinations are an ordered priority list filtered by
institution entitlement — *not* a fixed set of four; the shape must be right
at T5 because retrofitting means touching every role) and **D-27** (exactly
four bottom tabs, fourth is always More; tasks earn tab slots, hubs do not).
**D-26** (app bar carries status only, never actions) constrains the shell
chrome, and **D-30** the tab behaviour.

Blockers 1 and 2 are both due before T5 and are the only things I would want
closed first — the APK build in particular, since T5 is the first task whose
output is materially about mobile layout.
