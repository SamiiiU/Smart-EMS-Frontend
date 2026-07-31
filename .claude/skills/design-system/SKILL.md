---
name: design-system
description: Smart EMS design system — tokens, spacing and radius scales, elevation rule, and typography. Extracted from 14 high-fidelity screens.
user-invocable: false
paths: lib/**
---

# Design System

Authoritative source for colours, spacing, radii, and type in Smart EMS.
Never invent a value. If something you need is not here, stop and ask.

Implementation lives in `frontend/lib/core/theme/` — the only directory
permitted to contain raw colour or numeric literals. Everywhere else,
read tokens via `context.tokens` (`SmartEmsTokens`), `AppSpacing`,
`AppRadius`, and `AppTypography`. Enforced by
`frontend/tool/check_tokens.sh`.

## Tokens

Names are semantic. A screen asks for `surface`, never for `white`.

Columns are: token · light · dark

Surface
```
page              #FAFAF8   #191916
surface           #FFFFFF   #1F1F1C
surfaceSunken     #F2F2EE   #2B2B28
border            #E4E4DE   #2B2B28
borderStrong      #CFCFC7   #33332F
```

Text
```
textPrimary       #171715   #FAFAF8
textSecondary     #5C5C56   #A8A8A0
textMuted         #A8A8A0   #7C7C74
textDisabled      #CFCFC7   #5C5C56
```

Action
```
primaryAction     #0F7462   #0F7462   (identical in both — D-23)
primaryPressed    #0A5D4E   #0A5D4E
primaryAccent     #158A76   #158A76   NON-TEXT ONLY (borders, indicators)
primaryTextOnSurface #0F7462 #3F9E8D  primary AS TEXT — on surface/page ONLY (D-32, D-36)
primarySubtle     #E6F2EF   #0F3A31
onPrimary         #FFFFFF   #FFFFFF   (stays a token despite being equal)
```

Brand — decorative surfaces only, no actions ever sit on these
```
brandSurface      #0A5D4E   #0A5D4E
brandSurfaceDeep  #06463A   #06463A
onBrand           #FFFFFF   #FFFFFF
onBrandMuted      #C0DFD8   #C0DFD8
```

Semantic
```
success/successBg    #1B7F3B / #E8F3EA    #6FCF8B / #12301C
warning/warningBg    #B26B00 / #FBF0DE    #E0A24A / #331F04
danger/dangerBg      #B3261E / #FBEAE9    #F09490 / #351310
info/infoBg          #1B5E9E / #E7F0F8    #7FB3E0 / #12283D
successTextOnBg      #0E4520              #8FDDA5
warningTextOnBg      #5E3800              #EBBE7A
dangerTextOnBg       #5E1410              #F5B3B0
infoTextOnBg         #0E3253              #A8CBEA
```

Row tint
```
rowTintDanger     #FEF9F9   #241412
rowTintWarning    #FFFCF6   #231C11
```

## Scales

Fixed sets. Anything outside them is a defect, not a choice.

```
space1 2 · space2 4 · space3 6 · space4 8 · space5 12
space6 16 · space7 20 · space8 24 · space9 32 · space10 40

radiusSm 6 · radiusMd 8 · radiusLg 10 · radiusXl 12
radius2xl 14 · radiusFull 999
```

### Elevation rule (D-28)

Borders carry structure everywhere — cards, tables, panels, rows. Shadow
is reserved for genuine overlays only: bottom sheets, dropdowns, dialogs.
Expose exactly one shadow token, `shadowOverlay`. Nothing else has a
shadow.

Reason: shadows cost render time on low-end Android, read poorly at small
sizes, and are nearly invisible against a near-black dark surface — a dark
theme built on shadows loses its structure.

## Typography

Plus Jakarta Sans via `google_fonts`. Inter is the documented fallback if
low-end Android rendering proves weak — a note only, not a runtime switch.

```
28/600  parent status hero
24/600  screen title
20/500  section heading
18/500  card heading
16/500  person names, list primary
16/400  body — parent, student
15/400  body — teacher
14/400  body — admin, metadata
13/600  fieldLabel   form field labels        (presence)
13/500  timestamp    "Marked at 8:52 AM"      (recedes)
12/600  overline     uppercase section labels (presence)
12/500  caption      supporting text          (recedes)
```

Nothing below 12px. Exactly three weights: 400, 500, 600.

**Placement constraint (D-36):** `primaryTextOnSurface` is valid on `surface`
and `page` only. On `surfaceSunken` (table header band, break-row fill) it
misses 4.5:1 in dark — use `textPrimary` there. Use
`context.tokens.primaryTextOn(background)` where the background is known and
you want the constraint enforced rather than remembered.

**Contrast is CI-enforced.** `test/contrast_test.dart` asserts every pairing the
product renders, in both modes, against 4.5:1 (text) or 3:1 (non-text). Add a
pairing there when you introduce one — three real failures shipped through a
green suite before this existed, because contrast is invisible to widget tests
and to goldens.

THE FOUR SMALL STYLES WERE ONE PAIR OF MALFORMED ROWS. "12/500 overline,
caption" and "13/500 secondary label, timestamp" each put two different jobs on
one weight. A LABEL needs presence; SUPPORTING TEXT should recede. One weight
cannot serve both, which is why the weight flip-flopped across T2 and T3. Split
into four (twelve styles, still three weights). DO NOT merge them back in a
"consistency" pass — a test asserts both directions. See RULING 3.2.

Tabular figures on EVERY numeric style, via
`fontFeatures: [FontFeature.tabularFigures()]`. Counts, percentages, and
PKR amounts sit in columns and must align.

Base body size is set per role shell, not globally (D-24):
Parent 16 · Student 16 · Teacher 15 · Admin 14. Exposed as
`AppRole.baseBodySize` / `AppTypography.textThemeFor(role)` for T5 to
apply per shell.

### Sizing scale (T2)

Separate from spacing. Spacing is the gap between things; sizing is how big
an interactive thing is. `AppSizing`:

```
touchTargetMin 44        <- Phase 0 NFR, minimum on ALL interactive elements
button         sm 36 · md 44 · lg 48
field          desktop 40 · mobile 48
avatar         24 · 28 · 32 · 40 · 56
border         thin 1 · thick 2
statusGlyph    sm 12 (shape only) · md 22 · letterMd 13   (D-37)
progressBar    8
listRowMinHeight        56
periodTimeColumnWidth   44
tableCollapseBreakpoint 600
tabIndicatorHeight      2
```

On touch platforms every button size is raised to 44, so `sm` renders at
`md`'s height on mobile. That is deliberate — the NFR outranks the taxonomy.

## Primitives

Six primitives, in `lib/core/widgets/`. None contains a literal colour,
spacing, radius, or size. Every variant is rendered in the live gallery
(`lib/core/theme/primitives_gallery.dart`).

### StatusPill

The most-reused component in the product: attendance marking, admin
dashboard table, student profile counters, calendar legend, students list,
CSV import.

```
StatusPill(status, size: sm | md, showLabel: bool)

// D-37: a letterless pill is UNREPRESENTABLE. sm has no letter (12px cannot
// hold one), so sm requires showLabel: true. Only md attendance pills may
// set showLabel: false. Asserted const-evaluably -> compile error at const
// call sites.
```

**D-21 is load-bearing.** Every attendance status carries colour, letter,
AND shape together. Shape and letter are DERIVED from the status, not
constructor parameters, so a colour-only pill is unrepresentable in the API.

Reason: roughly 8% of men have some colour vision deficiency and teachers in
Pakistani schools are frequently men. If present and absent differ only by
green and red, a 40-student roll is misread and the failure is silent.

```
Present  P    filled circle           success / successBg
Absent   A    open circle, 2px ring   danger / dangerBg
Late     —    half-filled circle      warning / warningBg
Leave    Lv   filled circle           info / infoBg
Excused  E    dashed ring             textSecondary / surfaceSunken
```

Note: Present and Leave intentionally share the filled-circle shape per the
spec table, so the non-colour signal is the (shape + letter) PAIR, which is
unique across all five. A test asserts this. This is exactly why D-37 matters:
for that pair the letter is the ONLY non-colour differentiator, so an
illegible letter collapses it to colour alone.

The letter inside a FILLED glyph uses `onFilledGlyph(statusBg)` (D-38), which
inverts: white in light, the status `…Bg` in dark. Never pin it to white — that
is 1.91:1 on dark-mode success.

Entity statuses (`active`, `inactive`, `complete`, `notStarted`, `partial`)
render a label only — no letter, no shape.

### Avatar

Initials on a tinted circle. `primarySubtle` by default; the semantic role
when the row carries a status.

```
Avatar(initials, size: s24|s28|s32|s40|s56, tone: neutral|primary|semantic, status?)
```

`tone: semantic` requires a `status` to take its colour from (asserted).

### AppButton

```
AppButton(label, onPressed?, variant: primary|secondary|ghost,
          size: sm|md|lg, icon?, fullWidth: bool)
```

- primary — `primaryAction` fill, `onPrimary` text, `primaryPressed` on press
- secondary — 1px `primaryAccent` border (D-35), `primaryTextOnSurface` text, no fill
- ghost — `primaryTextOnSurface` text only, including when disabled

Only the filled variant gets a filled disabled state; secondary keeps its
outline and ghost stays text-only, so a disabled button never reads as
primary.

### AppTextField

```
AppTextField(label, value, placeholder?, obscure, trailing?,
             state: normal|focused|error|disabled, errorText?)
```

Label above the field, 13/600, `textSecondary`. Focused ring uses `primaryAccent` (non-text, 3:1). Height from `AppSizing`
(40 desktop / 48 mobile). Error state uses `danger` for border and message.

### Overline

`Overline(text)` — 12/600 (`overline`), `textSecondary`, 0.06em tracking, uppercased by the
widget. The original string is passed to `Semantics` in its natural case so
screen readers do not spell out an all-caps label.

### ProgressBar

`ProgressBar(percent)` — 8px tall, `radiusFull`, track `surfaceSunken`.

**Threshold: `>= 75` success, `< 75` warning. Two tiers only.** There is
deliberately no third danger tier. The below-75% treatment appears on parent
landing, parent calendar, admin profile, and the student's own screen and
must read identically in all four.

### Icons

Material Icons (`Icons.*`) is the single icon set for the project — see
DECISIONS.md D-T2-03. Do not introduce a second one.

## Composites

Nine composites, in `lib/core/widgets/`. Built only from primitives and
tokens. Every variant is in the live gallery
(`lib/core/theme/composites_gallery.dart`).

```
ContextStrip(icon, title, subtitle?, trailing?, tone: primary|neutral|semantic, status?)
InlineAlert(tone: info|warning|danger|success, message, icon?)
StatCard(value, label, tone: neutral|success|warning|danger|info, sub?, onTap?)
ListRow(leading?, title, subtitle?, trailing?, tint: none|danger|warning, minHeight: 56, onTap?)
PeriodRow(time, title, subtitle?, trailing?, isBreak, tint, onTap?)
HeroCardBrand(title, eyebrow?, subtitle?)                 <- NO action, ever
HeroCardTinted(title, action, eyebrow?, subtitle?)        <- action REQUIRED
SectionCard(child, title?, trailing?, padded)
AppDataTable(columns, rows, statusColumnLabel)
Tabs(tabs, selectedIndex, onSelected)
```

### Rules that are enforced, not just documented

- **InlineAlert is always inline and persistent. NEVER a snackbar.** Phase 3
  established that a message the user must act on cannot disappear on a
  timer. There is deliberately no `duration`, no auto-dismiss, no overlay
  variant, and no `onDismiss`. Do not add them.
- **ListRow: the WHOLE ROW is the tap target**, not just the trailing
  control — established on the attendance screen to reduce mis-taps.
  Implemented with `HitTestBehavior.opaque`; tests assert that a tap at the
  leading edge and a tap in the inter-child gap both fire `onTap`.
- **PeriodRow renders breaks as a muted row rather than omitting them.**
  A gap in a timetable reads as missing data.
- **HeroCard brand vs tinted is structural (D-23).** `HeroCard` is sealed.
  `HeroCardBrand` has no action parameter at all, so an action-carrying
  brand hero does not compile; `HeroCardTinted` makes `action` required.
  A primary button on `brandSurface` fails contrast, which is why there is
  no single class with an optional action.
- **AppDataTable collapses below 600px and NEVER scrolls horizontally.**
  Below the breakpoint each row becomes a card of `label: value` pairs, so
  no column is hidden. Asserted at 599 / 600 / 601 and 360px.
- **Tabs: a tab appears only when its content exists (D-19).** Pass
  `hasContent: false` and the tab is not rendered — not greyed out, not
  empty. `selectedIndex` indexes into the VISIBLE tabs.
- **SectionCard uses a border, never a shadow** (D-28).
- Semantic composites take their label colour from the `…TextOnBg` tokens
  and their icon/glyph colour from the saturated semantic colour, because
  text needs 4.5:1 and an icon or shape needs 3:1.

### Standing requirement from T3 onward

Every task must render without overflow at **360, 768 and 1366px**.

## Shell

_(pending seeding — T5)_

## Global states

Six components in `lib/core/widgets/states/`, plus the precedence rule that
decides which one a screen shows.

**The rule is the deliverable, not the widgets.** It is implemented once in
`resolveOutcome()` / `ScreenStateBuilder`. A screen supplies its data builder
and its empty/error copy — it never decides when a state beats data.

```
ScreenStateBuilder<T>(state, data:, onRetry:, emptyTitle:, emptyMessage:,
                      skeleton:, emptyActionLabel:, onEmptyAction:,
                      filterDescription:, onClearFilter:)
```

### Precedence — exactly one outcome, evaluated in order

| # | Condition | Renders |
|---|-----------|---------|
| 1 | offline, no cached data | `OfflineState` |
| 2 | offline, cached data exists | the data + offline indicator |
| 3 | loading, no prior data | `LoadingSkeleton` |
| 4 | loading, prior data exists | the prior data, refresh in background |
| 5 | error, no cached data | `ErrorState` |
| 6 | error, cached data exists | the data + non-blocking failure notice |
| 7 | loaded, zero rows, filter active | `FilteredEmptyState` |
| 8 | loaded, zero rows, no filter | `EmptyState` |
| 9 | `/me` returned 404 | `UnlinkedProfileState` |
| 10 | otherwise | the data |

**Rows 2, 4 and 6 are D-30: existing data is NEVER replaced by a state.** A
user who can already see rows does not lose them because a refresh failed or
the network dropped. Getting this wrong makes an app feel broken, not slow.
Row 7 before row 8 is D-14. Row 9 is checked first, inside the failure branch,
because `notLinked` is not an error and must never be offered a retry.

### The six

- **LoadingSkeleton** — `listRows` / `cards` / `tableRows` / `statCards`.
  Never a spinner. **Dimensions match the real content** — the list-row
  skeleton is exactly `AppSizing.listRowMinHeight`, so nothing shifts on load.
  Shimmer is opacity-only, stops on data, and stops under reduced motion
  leaving a static skeleton (the one exception to D-29's looping-animation
  ban).
- **EmptyState** — static icon, message, OPTIONAL single action. The action is
  governed by D-19: offer one only when it exists. A label without a callback
  is unrepresentable (asserted).
- **FilteredEmptyState** — a SEPARATE component (D-14), not `EmptyState` with a
  flag. States which filter matched nothing; the clear action is REQUIRED,
  because a filter the user cannot clear is a trap.
- **ErrorState** — backend message shown VERBATIM. Tracks its own retry
  attempts: after the second consecutive failure it says retrying is not
  working rather than re-rendering identically (D-11).
- **OfflineState** — reached only with no cached data. **Not an error, and must
  not look like one** — no danger colour, no failure icon. Offline is a mode,
  not a fault. No retry: retrying does not create a network.
- **UnlinkedProfileState** — 404 from `/staff/me` or `/students/me`. Not an
  error either: the login exists but was never linked to a person record (the
  D-17 orphan case). Points at the administrator. No retry — the user cannot
  fix it.

State icons use `textSecondary`, never `textMuted` (2.39:1 on surface).

### Emptiness is derived, not supplied (D-39)

`resolveOutcome` works out emptiness itself for `Iterable`, `Map`, and any type
implementing `HasRowCount` — which covers nearly every screen. `isEmpty` is an
OVERRIDE, not a required parameter.

If `T` is none of those and no override is given, it **throws**, naming both
fixes. It does not default to `false`, because that would silently skip rows 7
and 8 and render a blank area with no explanation.

- paged result type → implement `HasRowCount`
- single object that is never empty (a profile) → pass `isEmpty: false`

### Adding a seventh state

Check first whether it is genuinely new or one of these six under another
name. A seventh is a decision, not a convenience — record it in `HANDOFF.md`
rather than shipping it quietly.
