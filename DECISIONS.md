# Decisions

## Design decisions D-01 to D-31 — Phases 3–5

**These are NOT to be revised during implementation.** They are the design
decisions from Phases 3–5, and each carries its reasoning because the
reasoning is the point — without it these read as arbitrary style rules and
get "improved" away. Several exist specifically to prevent failures from the
previous build.

If implementation appears to require deviating from one of these, that goes in
`HANDOFF.md` under "Deviations from the prompt" and is **escalated, not
resolved locally**. That path has already caught the runtime font-fetch
problem and the in-memory DB seam; it is the mechanism that works.

D-32 onward are additions made during implementation and reviewed in.

---

## Navigation and structure

**D-01 — Sidebar on desktop, bottom nav on mobile. No drawer.**
*(revised by D-27 and D-31)*
A drawer hides destinations behind a hamburger: two taps plus a memory task.
Bottom nav keeps them visible — one tap, no memory. This is discoverability
cost, and it fails hardest on the Parent persona (low digital literacy, shared
phone, ~30-second sessions), which is where we can least afford it. Facebook
and Google both moved off hamburger navigation around 2014–16 with measurable
engagement gains.
Breakpoints: bottom nav under 600px, navigation rail 600–1024px, sidebar above
1024px.

**D-26 — The app bar carries status only, never actions.**
Teacher today briefly had two overflow controls — an app bar overflow and the
More tab — identical visual language, different destinations. The app bar is
also the hardest region to reach one-handed. Status (school name, sync
indicator, bell) stays; logout, profile and settings move into More. Desktop
is unaffected; the sidebar's pinned user block already serves this.

**D-27 — Exactly four bottom tabs, and the fourth is always More.**
*(revises D-01)*
Five tabs at 340px gives each 68px and labels cramp. Moving the overflow back
to the app bar was rejected — it reintroduces what D-26 fixed. Instead More
becomes the fourth tab. What gets demoted is settled by JTBD frequency, not
module importance: Today, Attendance and Diary are daily tasks; Classes is a
navigation hub to periodic work. **Tasks earn tab slots; hubs do not.**

**D-31 — Navigation destinations are an ordered list, filtered by institution
entitlement.** *(extends D-27, due at T5)*
Smart EMS sells pay-as-you-go; entitlement is institution-level, not
role-level (confirmed with Hasan). That keeps two filters independent:
entitlement asks *does this school have the module*, RBAC asks *can this user
act within it*.
The structural consequence is the whole point. Stored as a fixed set of four,
removing one destination leaves an empty slot and every role needs a switch
describing what fills it. Stored as an ordered priority list, the logic is:
filter by entitlement, take the first three, More is fourth — promotion
happens automatically because the list was already ranked. Parent's list is
My child, Attendance, Fees, Complaints, Messages, Profile, Settings; without
the Finance module, Fees drops and Complaints promotes with no code change.
No module store, no lock icons, no upgrade prompts, and no entitlement
endpoint exists yet. Only the shape of the list is at stake, and it must be
right at T5 because retrofitting means touching every role.

**D-30 — Tab state survives switching; returning never interrupts.**
No transition on tab switching (WhatsApp model). But instant switching only
reads as instant if nothing rebuilds on return — a refetch that resets scroll
reads as broken, which is worse than reading as slow. Four requirements
together: all four tabs stay alive (`StatefulShellRoute.indexedStack`,
`AutomaticKeepAliveClientMixin`); tab-level providers are `keepAlive`;
skeletons appear on first load only, never over data the user can already
see; scroll position is per tab.
Memory boundary: the four tabs stay alive, deep screens pushed on top
(student profile, marks entry, wizard) are ordinary push/pop and dispose
normally.
Stale data: render cache immediately, refresh in background, update in place.
A light refreshing indicator above the content if the cache is old — never an
emptied screen.

## Honesty about data

**D-07 — "Not marked yet" is a required third state.**
*(the most-reused decision in the product)*
Teachers mark attendance around 09:00; a parent may open the app at 08:45. If
the hero renders "absent" because no record exists, the parent believes their
child did not arrive — they panic, they call the school, and the failure is
invisible to us because nothing errored.
Generalisation: **anywhere a missing record could be misread as a negative
record, the missing case must be its own explicit state.** This recurs at
least four times — the parent hero, the dashboard table (an em dash, not a
zero), the attendance calendar (four distinct "empty" meanings), and the
timetable (breaks shown as rows, not gaps).

**D-15 — Attendance completeness is three states, not a boolean.**
`daily-summary` returns `markedCount` and `total` separately for this reason.
`markedCount == 0` means the teacher has not started (highest priority);
`< total` means partial; `== total` means complete. The dashboard table sorts
by status, not name — untouched first. Alphabetical sorting buries the rows
that need action and turns a worklist back into a report.

**D-19 — No affordance without a working backend.**
A control that looks available and does nothing is worse than no control: it
costs a click, produces confusion, and erodes trust in every other control on
the screen. Where an endpoint does not exist, either omit the control and
state the real alternative, or show it disabled with an honest label — never
an enabled control that fails.
Applies to: password reset (no link; footer says contact the school), report
card and receipt PDFs (disabled), file upload (omitted), user list and suspend
(not built), AI features ("coming soon" — routes exist, return 501), class
filter (omitted pending B-03).
Extension: tabs follow the same rule. A tab whose content belongs to an
unshipped tier is an empty destination. Tabs appear as their tier ships.
Student profile carries Overview and Attendance in Tier 1; Fees arrives with
Tier 2, Results with Tier 3.

**D-20 — Search must query the whole dataset or not exist.**
`search=` is accepted but ignored server-side (B-02). Filtering only the
loaded page produces a control that behaves like search but silently misses
records on other pages — a user searching for a student on page 5 sees "no
results" and concludes the student does not exist. Pilot approach: fetch the
full dataset once and filter client-side, genuinely complete at a few hundred
records. Beyond ~1,000, server-side search is required. If neither is
available, the control does not ship.

## Preventing the previous build's failures

**D-11 — Every card gets its states enumerated before layout is accepted.**
The current-period card looks like one component with one state. It has seven,
and "period in progress" — the easiest to design — is true for only a small
part of the day. In the previous build screens were designed for the happy
path and the rest was discovered in manual testing or not at all. That is why
the app looked broken outside narrow conditions. **A wireframe is not accepted
until every state of its primary component is listed.**

**D-17 — Multi-step creation flows use deferred commit.**
Creating a usable person needs two calls: `POST /api/users/provision`, then
`POST /api/staff` (or `/students`, `/guardians`) carrying the returned
`userId`. The obvious wizard fires call 1 on "Continue" — and that produced
the previous build's orphaned-login defect. An admin completed step 1 and
stopped; a login existed with no person record, there is no user list
endpoint, so the orphan was invisible and unrecoverable, and re-provisioning
the same username returns 409.
**A step boundary is a UI concept. It must not also be a commit boundary** —
committing early converts abandonment, a normal user behaviour, into
unrecoverable corrupt state.
Collect all input in local state; fire no network call until final submit.
Residual risk needs an explicit recovery state: call 1 can succeed and call 2
fail on a network drop. Hold the `userId` in memory and have retry reuse it —
never re-provision, or retry hits 409 and the admin is stuck.

**D-16 — Locked attendance rows must be visibly locked before interaction.**
Corrections lock 15 minutes after `server_recorded_at`, per student, not per
session. A 40-student roll marked over six minutes means the first locks at
minute 15 and the last at minute 21 — a teacher returning at minute 18 finds
some rows locked and some not. That is a common state, not an edge case.
If lock status is only discovered on submit, the teacher changes five rows,
submits, and three fail. **Partial failure is the worst possible outcome** —
they cannot tell what saved, and trust in the offline queue collapses.
Locked rows render as locked before any interaction. The backend message is
shown verbatim (it contains the next step). Edit affordances are
permission-gated on `attendance.manage`. A correction queued offline that
locks before sync returns 403 — the row must visibly revert and say why.
First-time marking never locks regardless of sync delay; the offline flow is
unaffected. Currently disabled in production
(`ATTENDANCE_CORRECTION_WINDOW_MINUTES=0`) until this ships.

**D-14 — The empty school is a distinct dashboard state, not a degraded one.**
*(two corrections)*
Rendering the normal dashboard with zeroes tells a new customer the product is
empty and broken. Show an onboarding checklist instead.
*Correction 1 — trigger.* Originally "all counters are zero". Wrong: on a
holiday or Sunday every counter is legitimately zero, so an established school
would see the onboarding screen every week. **Correct trigger: no sections or
students exist at all.**
*Correction 2 — order.* Originally students, classes, teachers. Wrong: CSV
student import requires a section to import into. **Correct order:
classes/sections, then import students, then add staff.**

## Interaction and layout

**D-02 — Attendance state control is frequency-weighted, not uniform.**
Five statuses, and five 44px targets plus a name and roll number do not fit a
360px row. Real distribution is skewed — roughly present 90%, absent 8%, late
1.5%, leave/excused 0.5%. Cost is matched to frequency: present 0 taps
(default), absent 1 tap (row or pill toggles), late/leave/excused 2 taps
(overflow opens all five). A 40-student class with 2 absent and 1 late costs
4 taps. This is what makes the 90-second target reachable.

**D-06 — The parent status hero is a sentence, not a statistic.**
"Attendance: Present" requires mapping a label to a value then interpreting
it. A percentage requires interpretation plus arithmetic. "Ayesha is present
today" requires neither. For a persona with limited digital literacy and a
30-second session, that difference is the 10-second target. The percentage
still appears, lower down — it answers a different, less frequent question.

**D-08 — Composed screens order sections by job frequency, not by module.**
The backend is organised by module; ordering a screen the same way mirrors the
database, not the user. Parent landing order: today's status, homework,
attendance %, fees, remarks, latest result.

**D-09 — Teacher Today carries the primary attendance action.**
Flow A targets 90 seconds end to end. Requiring the teacher to choose a
section costs time and introduces error, and the timetable already knows which
section is in front of them. The current-period card carries "Mark attendance"
pre-bound. The Attendance tab remains for corrections and out-of-sequence
marking.

**D-10 — Completed one-per-day tasks disappear rather than grey out.**
Self-attendance is once daily. A completed, disabled control sitting on the
teacher's most-visited screen for the rest of the day is persistent noise.
Remove it entirely.

**D-12 — Information density varies by persona, not by brand consistency.**
Density follows the persona, not a style preference. Admin works on desktop
all day and is fluent in Excel — low density wastes their time. Parent has a
30-second session and limited literacy — high density defeats them. Admin
screens are dense (tables, rows, inline actions); Parent and Student stay
sparse; Teacher sits between, dense where speed matters.

**D-13 — The admin dashboard's centre of gravity is the table, not the KPI
row.**
KPI cards answer *what is happening*. The admin's actual daily question is
*which section still has not marked attendance* — a per-row question with a
per-row action. A dashboard built only from KPI cards looks informative but
supports no decision. The table gets the space; KPIs are deliberately compact
so it stays above the fold.

**D-18 — Remembered context replaces repeated input.**
The institution never changes for a given user, so asking for it every login
asks them to re-supply a constant — and every memory task is a failure point
for the Parent persona. Captured once, then shown as a context strip with a
change action; the form drops from three fields to two. Change clears it; a
failed code clears it too.
Generalisation: **any value constant across sessions is captured once and
rendered as context, not re-requested.**

## Motion

**D-03 — Motion splits into functional and expressive.** Functional
communicates state and causality — it is interaction design, it affects
layout, so it is decided with the wireframes. Expressive carries personality
and depends on locked visuals.

**D-04 — Motion budget scales inversely with screen frequency.** On
high-frequency screens, duration is subtracted from the task budget: a 300ms
transition on a row tapped 40 times is 12 seconds of a 90-second target.
High-frequency screens 120–180ms, functional only. Low-frequency screens
250–400ms, expressive permitted.

**D-05 — Compositor-only animation, globally.** Animate `transform` and
`opacity` only. `width`, `height`, `top`, `left` trigger layout reflow and are
visibly janky on the budget Android this product targets.

**D-29 — Expressive motion is confined to reward and arrival moments.**
Earning moments: login entry 400ms; parent status hero reveal 300ms with scale
0.97 to 1 (the one thing they opened the app for — it should resolve, not
appear); dashboard KPI stagger 250ms, 60ms apart (the stagger is honest — each
KPI loads from its own endpoint, so simultaneous arrival would misrepresent
that); section reveal 200ms staggered; submit confirmation 250ms then settle
(the only overshoot in the product); onboarding checklist tick 300ms; empty
state entrance 250ms.
Easing: functional ease-out; expressive entrance `cubic-bezier(.2,.9,.3,1)`;
expressive settle `cubic-bezier(.2,1.3,.4,1)`, confirmation only.
Prohibited: transitions on tab switching (switched dozens of times a day —
instant is correct); looping or idle animation (battery); animated
illustrations in empty states (asset weight); parallax.
`prefers-reduced-motion` is respected — expressive motion off, opacity fades
only. **An accessibility requirement, not an option.**

## Visual system

**D-21 — Attendance status is never carried by colour alone.**
Roughly 8% of men have some colour vision deficiency, and in Pakistani schools
teachers are frequently men. Green-vs-red alone means a misread 40-student
roll, and the failure is silent — nothing errors. Every status carries three
signals: **colour, letter, shape.** Colour is reinforcement; letter and shape
carry the information. This is also why the attendance calendar's legend is
mandatory rather than optional.

**D-22 — Warm neutrals, not pure or cool grey.**
Teal-900 surfaces were rejected for content screens: the primary action loses
separation on a surface of its own hue; semantic colours pick up a cast,
weakening the separation D-21 depends on; saturated surfaces tire the eye over
all-day admin sessions; student photos read as tinted. Pure grey reads
clinical.

**D-23 — One primary action colour, identical in both themes.**
*(scope extended by D-32)*
The WhatsApp model, and it only works inside the luminance band where a colour
clears contrast against both white and near-black. Teal 700 is outside it. The
filled button is what this fixes — `primaryAction` with `onPrimary`, 5.68:1 in
both modes.
**Scope, and it matters:** this applies only to the primary action *as a
fill*. Everything sitting *on* a surface remaps — pills, avatar tints,
semantic backgrounds, and (per D-32) primary-coloured text.
Corollary: the rule runs both ways. A card that carries an action cannot use a
brand surface — the current-period card uses `primarySubtle`, because a
primary button on `brandSurface` fails contrast. **No action on brand
surfaces; tinted surfaces where an action lives.**

**D-24 — Base body size varies by persona surface.** Parent and Student 16px,
Teacher 15px, Admin desktop 14px. A single base size is wrong in both
directions — 14px defeats a parent on a small phone; 16px wastes a 1366px
admin table. Enforced by role being a required theme parameter so a global
default cannot creep back.

**D-25 — Typeface: Plus Jakarta Sans.** Chosen over Inter for warmth without
losing clarity, with proper tabular numerals — counts, percentages and PKR
amounts all sit in columns, and without tabular figures numbers shift as
values change. **Must be bundled, not fetched:** `google_fonts` downloads over
HTTP on first launch, so a cold offline install in a low-connectivity
institution renders in the platform fallback and discards the entire
specification in exactly the conditions the product is built for.

**D-28 — Structure is carried by borders, not shadows.** Shadows cost render
time on low-end Android, read poorly at small sizes, and are nearly invisible
against a dark surface — so a dark theme built on shadows loses all its
structure. Borders define structure; shadow is reserved for genuine overlays
where depth is real.

---

## Implementation additions (reviewed in)

**D-32 — The primary ramp has three distinct jobs.** *(extends D-23)*
No single colour can serve as primary-coloured TEXT in both themes: clearing
4.5:1 requires luminance <= 0.1833 against `#FFFFFF` and >= 0.2360 against
`#1F1F1C`, and those windows do not overlap. This is arithmetic, not a matter
of choosing a better teal. It is also **not an exception to D-23** — D-23
fixes the primary action *as a fill*, and text sitting on a surface was always
supposed to remap, exactly as `successTextOnBg` remaps.

The ramp therefore has three jobs, which retroactively justifies the
`primaryAccent` name introduced during T3:

| Token | Job | Light | Dark |
|-------|-----|-------|------|
| `primaryAction` | fill (D-23, identical both modes) | `#0F7462` | `#0F7462` |
| `primaryAccent` | non-text accent, borders, indicators | `#158A76` | `#158A76` |
| `primaryTextOnSurface` | primary colour AS TEXT on a surface | `#0F7462` | `#3F9E8D` |

`#3F9E8D` is primary 400 and measures 3.24:1 on white, which is why it is
dark-only. Applies to the secondary and ghost button labels and any future
primary-coloured text. Does NOT apply to the filled button, the focused ring,
the Tabs indicator, or borders.

Rejected alternative: using `textPrimary` for those labels in dark. It makes
the secondary button read as two different components across modes — a small
hue shift preserves identity, a white label destroys it.

**D-33 — The four small type styles are separate, and must not be merged.**
*(RULING 3.2)*
The type table previously carried two rows that each put two different jobs on
one weight: "12 · 500 | Overline, caption" and "13 · 500 | secondary label,
timestamp". Overline is a LABEL (TODAY'S HOMEWORK) and needs presence; caption
is SUPPORTING TEXT (86 of 121 school days) and should recede. One weight cannot
serve both, which is why this weight flip-flopped across T2 and T3 — the row
was malformed, so every attempt to "resolve" it was resolving the wrong thing.

```
overline     12/600   uppercase section labels   (presence)
caption      12/500   supporting text            (recedes)
fieldLabel   13/600   form field labels          (presence)
timestamp    13/500   "Marked at 8:52 AM"        (recedes)
```

Twelve styles instead of ten. That is fine — **the constraint was three
weights, not a style count**, and three weights still hold.

A test asserts BOTH directions and that the pairs genuinely differ, so neither
an upward nor a downward merge can be silent.

Note on one case that looks like an exception but is not: the **AppTextField
error message is 13/600**, the same weight as the label. An error is supporting
text by position but not by function — it must be noticed. It is distinguished
from the label by colour, not weight. Do not demote it to 500 on the grounds
that it sits below the field.

**D-34 — Brand sub-text is `#C0DFD8`, not `#94C9BE`.** *(RULING 3.3)*
`onBrandMuted` at `#94C9BE` measured 4.22:1 on `brandSurface`, under the 4.5:1
floor. Raised to primary 100, `#C0DFD8`, which clears it at 5.50:1 for a
visually slight change. This token appears on the login header and the parent
status hero — both first-impression surfaces, and the parent hero is the single
thing the Parent persona opens the app to read. Treated as a legibility
question, not a brand one. Mode-fixed in both themes, consistent with D-23's
treatment of brand colours.

**D-35 — The secondary button's border is `primaryAccent`.** *(RULING 4.1;
supersedes the "do not change borders" clause of RULING 3.1)*
The secondary variant has **no fill**, so its border is the control's only
boundary. On `primaryAction` it measured 2.91:1 against the dark surface —
below even the 3:1 non-text floor — which means the label was legible while
the button's extent was not. A user could read the control without being able
to see where it ended. That is a usability failure, not a polish item.
`primaryAccent` gives 3.88:1 and matches how the focused ring and Tabs
indicator were already handled.

The resulting two-tone control is correct, not a compromise: label on
`primaryTextOnSurface`, border on `primaryAccent`. In light the border reads
lighter than the label; in dark, a `#3F9E8D` label against a `#158A76` border —
the label is more prominent in both. **Text ahead of its container edge is the
right relationship.**

Unchanged: the filled button, the focused ring, the Tabs indicator, and the
ghost variant (which has no border to fix).

**D-36 — `primaryTextOnSurface` is valid on `surface` and `page` only.**
*(RULING 4.2)*
It measures 4.39:1 against `surfaceSunken` in dark — a 2.4% shortfall on a
pairing nothing currently uses. Shifting the token again to close that would
ripple through every placement that already passes, to fix one that does not
exist. So the token is unchanged and the **placement** is constrained instead.

On `surfaceSunken` — the table header band and the break-row fill — primary
-coloured text is not used; `textPrimary` is used there.

Written down because `surfaceSunken` is plausible T4/T5 territory: someone will
reach for a teal label on a table header and it will silently miss the floor.
Enforced three ways rather than remembered — a guarded accessor
(`SmartEmsTokens.primaryTextOn(background)`) that asserts the background is
`surface` or `page`, a test that the accessor rejects `surfaceSunken`, and a
test asserting the 4.39:1 shortfall still exists so the ban cannot be assumed
stale.

**D-37 — The status glyph letter clears the 12px floor, or there is no
letter.** *(RULING 5.1 — fixes a real D-21 failure)*
The letter was previously sized as a ratio of the glyph diameter, which
produced **6.96px** at `sm` and **9.28px** at `md`, both under the system's own
"nothing below 12px". At 6.96px the mark is not merely unread, it is **not
discriminable** — and because Present and Leave share a filled circle, the
letter is that pair's *only* non-colour differentiator. So the pair degraded to
colour alone: the exact failure D-21 exists to prevent, for the population it
protects.

Rejected: exempting glyph letters from the type floor on the grounds that a
mark is not a word. The argument fails on the facts — the mark was not
discriminable, so the exemption would just have been a way of not fixing it.

| Size | Glyph | Letter | |
|------|-------|--------|--|
| `md` | 16 → **22px** | **13px** | clears the floor |
| `sm` | 12px | **none** | `showLabel: true` required |

At 12px no font size yields a legible letter, so the small pill carries **shape
only** and shows the word instead.

Asserted, not documented: a letterless pill is **unrepresentable**. The
`StatusPill` constructor asserts `showLabel || (md && attendance)`, written as
a const-evaluable disjunction so const call sites fail at COMPILE time rather
than only in debug. Same pattern as `HeroCardBrand` having no `action`
parameter and `primaryTextOn` rejecting `surfaceSunken` — that pattern has now
caught four classes of error.

**D-38 — The filled-glyph letter uses an inverting token.** *(RULING 5.2)*
`onFilledGlyph(statusBg)` — `#FFFFFF` in light, the status's own `…Bg` in dark.

The T3 implementation used `…Bg` in both modes. Right in principle, 1.1% short
in light: `successBg` `#E8F3EA` is near-white but not white, giving **4.45:1**
on `success` `#1B7F3B`. White gives **5.07:1**. Dark keeps `…Bg`, which is what
fixed the original hardcoded-white bug — white on dark-mode `success`
`#6FCF8B` measures **1.91:1** and is unreadable.

Same shape as `onPrimary`: a foreground that follows its background rather than
being pinned to either end. Implemented as a method on `SmartEmsTokens`, which
required adding a `brightness` field to the extension.

Rejected: darkening the success ramp. It would ripple through every success
pairing already passing at 9.75:1 to fix one glyph.

*Figure note:* RULING 5.2 stated white-on-success as 4.72:1; it measures
**5.07:1**. The conclusion holds with a larger margin than stated. The same
formula reproduces the ruling's other figure (4.45:1) exactly, so 4.72 appears
to be the outlier. Asserted at 5.07 in `contrast_test.dart`.

## Task-time decisions (appended as tasks proceed)

### T0 — 2026-07-30

- **D-T0-01**: Dropped `riverpod_generator`, `riverpod_lint`, and
  `custom_lint` from the dependency set. `riverpod_generator` cannot
  resolve alongside `drift_dev` under any version combination tried
  (`source_gen`/`analyzer` version fragmentation across the riverpod 2.x
  and 3.x/4.x lines — see HANDOFF.md for the tested combinations).
  `drift`/`drift_dev` were kept because the native/web conditional export
  (Deliverable 7) directly guards the exact failure mode (`dart:ffi` on
  web) that broke the previous build. `riverpod_lint` was the cheaper
  loss since token/spacing enforcement in this project comes from
  `tool/check_tokens.sh` + the PostToolUse hook, not from a lint plugin.
  Decided by Sami during T0. Revisit once the codegen ecosystem versions
  line up.
- **D-T0-02**: Riverpod providers will be hand-written (no `@riverpod`
  codegen annotations) until D-T0-01 is revisited.
- **D-T0-03**: Repo root stays at SmartEMS (not narrowed to `frontend/`
  as its own repo), with `backend/` (Ali's separate clone) excluded via
  `.gitignore`. This is only safe because of the `.githooks/pre-commit`
  guard added alongside it: `.gitignore` alone is one `git add -f` away
  from letting `backend/` get committed here, so the pre-commit hook
  (rejecting any staged path under `backend/`) is what actually makes
  this layout safe, not the `.gitignore` entry by itself. Requires
  `git config core.hooksPath .githooks` once per clone (documented in
  README.md).

### T1 — 2026-07-30

- **D-T1-01**: `shadowOverlay` values were NOT supplied by the T1 spec,
  unlike every colour token. Implemented as a single `BoxShadow` at
  `blurRadius: 16`, `offset: (0, 4)`, colour `#171715` at 12% alpha in
  light and pure black at 40% alpha in dark (deeper in dark because a
  near-black surface swallows a soft shadow). These are DERIVED, not
  specified — flagged for confirmation. If they are wrong, only
  `tokens.dart` changes.
- **D-T1-02**: Spacing and radius scales are plain compile-time constants
  (`AppSpacing`, `AppRadius`) rather than fields on the `SmartEmsTokens`
  ThemeExtension. They are mode-independent — a gap is the same width in
  light and dark — so there is nothing for `lerp` to interpolate, and
  putting them in the extension would imply otherwise.
- **D-T1-03**: `AppTheme.light()`/`dark()` take `role` as a REQUIRED
  parameter with no default. D-24 says base body size is per role shell,
  not global; a default would quietly reintroduce a global one.
- **D-T1-04**: Tabular figures applied to ALL ten text styles, not a
  subset judged "numeric". Attendance counts, percentages, and PKR amounts
  appear at every size and in every role, so no style is safely
  proportional. Enforced by a test that iterates `AppTypography.all`.
- **D-T1-05**: `ColorScheme` is populated from the tokens as a Material
  interop shim only, because Material's own widgets read `ColorScheme`.
  `SmartEmsTokens` is authoritative — components from T2 onward must read
  the extension via `context.tokens`, never `ColorScheme`. Two slots have
  no corresponding token (`onError` in each mode) and are mapped to the
  nearest token with an inline comment explaining the choice.

### T2 — 2026-07-30

- **D-T2-01**: `shadowOverlay` values (D-T1-01) reviewed and **approved
  as-is**. The provenance comment in `tokens.dart` records that they were
  derived rather than specified, so a future reader does not mistake them
  for spec-exact values.
- **D-T2-02** (resolved spec conflict — do NOT "fix" this back): Phase 5
  described Overline as **12/600**. The T1 typography table specifies
  **12/500** for overline and caption. The type scale is the authority and
  the system has exactly three weights, so Overline is **12/500**. Asserted
  by a test (`overline is 12/500, not 12/600`) so a silent revert fails CI.
- **D-T2-03**: **Material Icons is the project's single icon set.**
  `Icons.*` from `package:flutter/material.dart` — currently used for the
  theme toggle, `AppButton.icon`, and the `AppTextField` trailing slot. No
  second icon set (no `lucide`, `phosphor`, `font_awesome`, custom SVG
  sheet) may be introduced without superseding this decision. Reason: two
  icon sets in one product means two visual weights, two grid sizes, and
  two licences, and the mismatch is obvious next to a strict type scale.
- **D-T2-04**: Plus Jakarta Sans is **bundled** as a pubspec asset
  (`assets/fonts/`, weights 400/500/600 only) and
  `GoogleFonts.config.allowRuntimeFetching = false`. There is now no
  network path for fonts. Reason: institutions are in low-connectivity
  areas and a cold offline first launch previously fell back to the
  platform font, discarding the whole type spec. Licence: SIL OFL,
  `assets/fonts/OFL.txt`. This also made the golden test viable, so it is
  restored and green.
- **D-T2-05**: Sizing lives in a **separate scale** (`AppSizing`) from
  spacing (`AppSpacing`). Spacing is the gap between things; sizing is how
  big an interactive thing is. They have different constraints — the
  spacing scale tops out at 40, below the 44px touch-target NFR — and
  conflating them is how a 44px target quietly becomes 40px.
- **D-T2-06**: `StatusPill` derives shape and letter FROM the status; they
  are not constructor parameters. This makes a colour-only attendance pill
  unrepresentable in the API rather than merely discouraged, which is what
  D-21 requires.
- **D-T2-07**: On touch platforms every `AppButton` size is raised to
  `AppSizing.touchTargetMin` (44). Consequence: `sm` (36) renders at the
  same height as `md` on mobile, making `sm` effectively a desktop/compact
  size. Accepted deliberately — the NFR outranks the size taxonomy.
- **D-T2-08** (checker correctness): `check_tokens.sh` had a latent bug
  from T0 — its `EdgeInsets`/`BorderRadius` rules flagged any digit inside
  the parens, so *correct* code like
  `EdgeInsets.symmetric(horizontal: AppSpacing.space6)` was a violation
  because the token NAME contains `6`. It never fired in T0/T1 because no
  code outside `lib/core/theme/` used the scales yet. Fixed to only flag a
  digit in a VALUE position (immediately after `(`, `:` or `,`). Also added
  a windowed rule for multi-line `SizedBox` so `height:` on a `TextStyle`
  (a line-height multiplier, not a dimension) is not misread as a size.

### T3 — 2026-07-30

- **D-T3-01 — REVERSES D-T2-02.** D-T2-02 recorded "Overline is 12/500, do
  not fix it back to 600" and treated the T1 table as authoritative. **That
  was wrong.** Phase 5 is the design authority; the T1 table entry was a
  transcription error, and 600 was always one of the three available
  weights, so there was never a constraint forcing 500. Corrected:
  **Overline is 12/600** and the **AppTextField label is 13/600**.
  The reversal is kept rather than deleted because the useful record is that
  "the type scale is the authority" was applied to a row that had itself
  been mis-transcribed — check the source, not the transcription.
  The guard test now asserts 600 and is named to say it reverses the T2 one.
  *Interpretation flagged:* the two corrected rows are the table rows shared
  with "caption" (12) and "timestamp" (13), so those move to 600 too. If only
  the two named components were meant to change, that is a one-line split.
- **D-T3-02 (RULING 2.1)**: Overline colour `textMuted` → `textSecondary`.
  `#A8A8A0` on `#FFFFFF` measured 2.39:1 against the 4.5:1 AA floor, and
  12px is not "large" under WCAG. Overline is a section LABEL, not
  decoration, so `textSecondary` is both accessible (6.73:1) and the more
  correct semantic.
- **D-T3-03 (RULING 2.2)**: `StatusPill` label text now uses the
  `…TextOnBg` tokens. `coloursFor` returns three roles — `bg`, `text`
  (`…TextOnBg`, 4.5:1 floor) and `glyph` (the saturated semantic colour,
  non-text, 3:1 floor). T2 used the glyph colour as text, which measured
  3.73:1 for Late and 4.45:1 for Present. Also fixed a latent dark-mode
  bug: the letter inside a FILLED glyph was hardcoded to white, which is
  unreadable on dark-mode `success` `#6FCF8B`; it now uses the pill's own
  `…Bg` token, which inverts correctly by mode.
- **D-T3-04 (RULING 2.3)**: primary ramp shifted one step darker —
  `primaryAction` `#158A76` → `#0F7462`, `primaryPressed` `#0F7462` →
  `#0A5D4E`. `primaryAccent` `#158A76` added so the old value stays
  available for NON-TEXT use (borders, indicators) as the ruling required.
  This makes 32 colour tokens, not 31.
- **D-T3-05**: The focused field ring and the Tabs indicator use
  `primaryAccent`, not `primaryAction`. Both are non-text (3:1 floor), and
  after the ramp shift `primaryAction` measures only **2.91:1** against the
  dark surface — it fails even 3:1 there, while `primaryAccent` passes at
  3.88:1. This is precisely the use RULING 2 retained `primaryAccent` for.
- **D-T3-06**: `AppDataTable`, not `DataTable` — Flutter's Material library
  already exports `DataTable`. Same rationale as `AppButton`/`AppTextField`.
- **D-T3-07**: `HeroCard` is a **sealed** class with two concrete subclasses,
  `HeroCardBrand` (no action parameter exists) and `HeroCardTinted`
  (`action` is REQUIRED). Not one class with an optional action — that shape
  is exactly what would let a button land on `brandSurface` and fail
  contrast. The compile-time guarantee cannot be asserted at runtime, so the
  test asserts the observable consequence: a brand hero contains no
  `AppButton` and no `GestureDetector` anywhere in its subtree.
- **D-T3-08**: `AppDataTable` collapses at `< 600px` (so exactly 600 is
  wide) and contains no horizontal scrollable at all. Below the breakpoint
  each row becomes a card of `label: value` pairs so no column is hidden.
  Asserted at 599 / 600 / 601px and at 360px.

**D-39 — Emptiness is DERIVED by default; explicit only when it cannot be.**
*(RULING 6.1)*
`isEmpty` was a parameter every screen had to remember, which left one hole in
an otherwise closed rule: a screen that forgot it silently skipped rows 7 and 8.
An `int Function(T)` does not close that — the caller still supplies the
function and can supply a wrong one. It relocates the mistake rather than
removing it.

So: **make the common case automatic and the exotic case loud.**
`resolveOutcome` derives emptiness itself for `Iterable`, `Map`, and any type
implementing `HasRowCount` (which the paged result type will), covering nearly
every screen in the product. `isEmpty` becomes an OVERRIDE.

When `T` is none of those and no override is given, it **throws**. Defaulting
to `false` is the dangerous branch: it silently skips rows 7 and 8 and renders
a blank area with no explanation — the previous build's failure exactly.
Throwing surfaces the omission at first render, in development, naming the
screen. The message states both fixes (implement `HasRowCount`, or pass
`isEmpty: false` for a single object that is never empty).

Derivation is only reached on the loaded path, so an underivable type does not
throw while loading, erroring, or offline — a profile screen must not crash
before it has data. Asserted.

**D-40 — `ScreenState<T>` stands, rather than Riverpod's `AsyncValue`.**
The precedence rule turns on whether PRIOR DATA EXISTS. `AsyncValue` expresses
that as `hasValue` on a loading/error state, which is easy to overlook — and
overlooking it silently breaks D-30, the rule that stops a refresh from
blanking rows the user can already see. As a named field on a purpose-built
type it cannot be missed. T6 supplies a thin adapter from `AsyncValue`.
`OfflineBanner` is confirmed as the row-2 adornment, not a seventh state.

**D-41 — JWT claim shape, VERIFIED against a real decoded token (T7).**
*(2026-08-03. Supersedes every prior assumption; nothing about this was
actually verified before.)* Decoded from a live `/auth/login` response:

```json
{ "sub": "<uuid>", "tid": "<uuid>", "roles": ["admin"],
  "permissions": ["attendance.manage", "...21 entries"],
  "iat": 1785744423, "exp": 1785745323 }
```

- **`tid` (tenant) and `roles` (array) were assumed correct — and they
  ARE.** `CLAUDE.md`'s guidance stands, now on evidence rather than
  assertion.
- **`permissions` is a claim nobody had documented** — a flat array of
  `resource.action` strings. This is finer-grained than `roles` and is the
  natural key for future capability gating. Not used yet; recorded so T8+
  does not re-derive permissions from role names when the token already
  carries them.
- **Access token: HS256, 15-minute lifetime** (`exp - iat = 900`), matching
  the `expiresIn: 900` field.
- **The refresh token is NOT a JWT** — it is an opaque 36-char UUID, i.e. a
  server-side session handle. It carries no readable claims and must not be
  parsed.

**D-42 — Bearer-token auth is retained; cookie auth reconsidered and
explicitly rejected.** *(T7, closing the T6 flag.)* Railway now returns
`Access-Control-Allow-Credentials: true`, which the old local Docker image
did not — so the original "cookies are impossible" justification no longer
holds. Reconsidered on the merits anyway and **bearer is kept**, because the
deployed API documents itself that way (`securitySchemes: bearerAuth`,
`scheme: bearer`, `bearerFormat: JWT`, applied globally, with the
description "Send `Authorization: Bearer <accessToken>` on every /api/**
call"). Switching to cookies would mean diverging from the backend's own
declared contract for no gain, and would not survive the Flutter mobile
targets, where there is no cookie jar to rely on. Recorded so this is not
re-litigated: the reason is the backend's declared contract, not the CORS
header.

**D-43 — The identity gate is a TWO-step resolution, and `notLinked` is
keyed off the person-record endpoints.** *(T7.)* Verified live: `/auth/me`
returns 200 for any valid token, so it cannot express D-17's orphan case;
`/api/staff/me` and `/api/students/me` return
`404 "… record linked to this login not found"` when the person row is
missing. So `NetworkIdentityResolver` calls `/auth/me` first (validity +
`roles`), then the person endpoint **only for roles that require one**.
Roles `admin` / `owner` / `super_admin` / `parent` are skipped entirely —
an admin legitimately has no staff row, and treating its 404 as `notLinked`
would show "your profile is not linked, contact your administrator" to the
very person who resolves such cases. `parent` is skipped because the API
exposes no `/api/guardians/me`; if parents turn out to need a person check,
that endpoint has to exist first.

**D-44 — There is no self-signup, and the login screen says so rather than
implying one.** *(T7.)* No unauthenticated account-creation endpoint exists
in any of the 124 documented paths; `POST /api/users/provision` requires an
existing admin token, and login requires an `institutionCode`, so accounts
live inside an institution that already exists. The login screen therefore
carries **no "create account" control** — that would be a false affordance
(D-19), a control that cannot lead anywhere. It states plainly that accounts
come from the institution's administrator, the same reasoning as
`UnlinkedProfileState`: when the user cannot self-serve, name who can.

**D-45 — `AppTextField` became a real input; it had never been one.**
*(T7, by ruling.)* The T2 primitive rendered `Text(value)` with no
`EditableText`, no focus handling, and an `onChanged` that was declared but
wired to nothing and could never fire — a text field that could not accept
text. It went unnoticed because T7 is the first task to build a form. It now
wraps a `TextField` with the public API, every token and the full visual
contract unchanged (verified against regenerated goldens across all six
states). Two consequences worth recording: an explicit non-`normal` `state`
still wins, but `normal` now derives the focus ring from **real** focus; and
the old `obscure` test asserted a literal `'••••'` string, which was a
property of the mock's rendering rather than of obscuring — it now asserts
`TextField.obscureText`, paired with a positive non-obscured case.

**D-T8-01 — Attendance shapes come from LIVE probing, not the OpenAPI doc.**
*(2026-08-05.)* The published schema for `POST /api/attendance` and
`/api/attendance/bulk` is **wrong**: springdoc collided identically-named
inner DTOs (`MarkBody`/`BulkBody`/`BulkRow` exist in both
`AttendanceController` and `StaffAttendanceController`) and published the
STAFF schema for the STUDENT endpoints. Building from it would have posted
`staffId` where `studentId` is required. Real shapes were obtained by
POSTing `{}` and reading the 400's `details`. **The OpenAPI document is a
lead, not a contract** — that is now three separate failures (missing
`/internal/bootstrap/*`, this, and untyped timetable responses). Status enum
is lowercase `present|absent|late|leave|excused`, matching `StatusPill`'s
five attendance variants exactly.

**D-T8-02 — Bulk-first, corrections through the single endpoint.** The queue
stores marks uniformly and replays them by kind: non-corrections grouped by
section+date into ONE `/api/attendance/bulk` call, corrections one at a time
through `/api/attendance`. `clientUuid` is generated on the device before
any request is attempted — it is the backend's required idempotency key
(the response carries `idempotentReplay`), which is what makes replaying a
queued register safe. Re-marking a student REPLACES their queued row rather
than appending: the queue holds intent, not a keystroke log, and two
contradictory rows would make the result depend on send order.

**D-T8-03 — Conflict rule: server wins, and the local value is never sent.**
Server state is read BEFORE sending, because the bulk response reports only
counts and would destroy the evidence. Where a queued mark disagrees with
what the server already holds, our value is **not transmitted at all** —
transmitting it would overwrite the authoritative record, the opposite of
"server wins". The disagreement is recorded to a `attendance_conflict`
table and surfaced as a non-blocking inline notice. Conflicted marks still
leave the queue: retrying them would never succeed.

**D-T8-04 — The lock window has no `== 0` branch anywhere.** Production is
0 today; that is treated as a real value ("no grace beyond the attendance
date"), not a special case. The same arithmetic grants real extra time the
moment Ali configures a non-zero window, with no frontend change — asserted
by a test that exercises both 0 and 1 day. A locked register renders an
explanation naming who can help, never a bare disabled control.

**D-T8-05 — `AppButton` labels ellipsize instead of overflowing.** *(T2
change.)* `AppButton` laid its label out in a `Row` with no flex, so any
label too long for the button's fixed height overflowed — `'Submit
attendance'` on a full-width button overflowed by 2.4px at a 2× text scale
on a 360px phone. Same class of defect as `AppTextField` in T7: a shared
primitive that fails only under conditions no earlier task exercised. The
label is now `Flexible` with `maxLines: 1` + ellipsis. It is a safety net,
not a licence — the attendance screen still uses the shorter `'Submit'`,
because a truncated verb is worse than a brief one.

**D-T8-06 — Two contrast assertions were withdrawn as over-strict, not as
inconvenient.** Idle chip borders (`border`, ~1.28:1) and disabled labels
(`textDisabled`, ~1.57:1) do not clear the 3:1 non-text floor. Neither is a
defect: WCAG 1.4.11 exempts inactive components outright, and an idle
border is decorative refinement on a chip already identified by its own
text label. `border` has been used exactly this way for every card and
sidebar since T3. The SELECTED border, which is genuinely load-bearing, IS
asserted.

### T4 — 2026-07-30

- **D-T4-01**: The precedence rule is implemented ONCE, in
  `resolveOutcome()` + `ScreenStateBuilder`. A screen supplies its data
  builder and its empty/error copy; it does not get to decide when a state
  wins over data. This is the actual deliverable of T4 — six widgets are
  the easy part, and built per-screen the ordering drifts, which is exactly
  how the previous build ended up with a spinner on one screen, a blank
  area on another, and "no results" indistinguishable from "not loaded yet".
- **D-T4-02**: `ScreenState<T>` is a purpose-built type rather than
  Riverpod's `AsyncValue`. The rule turns on whether PRIOR DATA EXISTS,
  which `AsyncValue` expresses as `hasValue` on a loading/error state —
  easy to forget, and forgetting it silently breaks D-30. As a named field
  it cannot be overlooked.
- **D-T4-03**: Row 9 (`/me` 404 → `UnlinkedProfileState`) is evaluated
  FIRST, inside the failure branch, not after rows 5/6. A `notLinked`
  failure is not an error and must never be offered a retry — including
  when cached data exists, where the generic error path would otherwise
  render the stale data and hide the fact that the profile was never
  linked.
- **D-T4-04**: `isEmpty` is an explicit field on `ScreenState`, not
  inferred from the data. `T` may be a list, a page object or a record, so
  there is no general way to ask "does this have zero rows" — and guessing
  is how row 7/8 would silently stop firing.
- **D-T4-05**: Shimmer is opacity-only, stops on dispose (which the
  precedence rule triggers the instant data arrives), and stops under
  `prefers-reduced-motion` leaving a STATIC skeleton rather than none. It
  is the one permitted exception to D-29's ban on looping animation,
  because D-29 prohibits *idle* animation — motion with nothing behind it —
  and a shimmer communicates active work. A fully static skeleton reads as
  stuck.
- **D-T4-06**: `ErrorState` tracks its own retry attempts. After the
  second consecutive failure it stops presenting the same face and says
  retrying is not working (D-11's "enumerate the retry path"). The counter
  lives in the component because every caller would otherwise have to
  remember to implement it.
- **D-T4-07**: State icons use `textSecondary`, never `textMuted`.
  `textMuted` measures 2.39:1 on `surface`, below the 3:1 non-text floor —
  the same value that failed for Overline in RULING 2.1. Caught by the
  contrast suite the moment the components were written.

### Carry-forward items (not decisions — logged so future-you doesn't relearn them)

- **PROVEN IMPOSSIBLE: D-23 cannot coexist with AA text contrast for a
  primary colour used AS TEXT.** D-23 fixes `primaryAction` identical in
  both modes. For 4.5:1 as text it must satisfy **L ≤ 0.1833** (to clear
  `#FFFFFF`) and **L ≥ 0.2360** (to clear `#1F1F1C`). Those windows do not
  overlap, so **no colour whatsoever** satisfies both — this is arithmetic,
  not a matter of picking a better teal. Consequence after the T3 ramp
  shift: light mode now passes everywhere, but in DARK mode the secondary
  button label measures **2.91:1** and the ghost label **3.10:1**. Both are
  visible in `test/goldens/composites_dark.png` — the "Done" and "View all"
  ghost labels are barely legible. At the 3:1 NON-TEXT floor the window IS
  feasible (0.1407 ≤ L ≤ 0.3000), which is why borders and indicators are
  fine on `primaryAccent`. Resolving this needs a design ruling, e.g. a
  mode-varying token used only when primary appears as text (a narrow,
  explicit exception to D-23), or accepting textPrimary for those labels in
  dark. NOT changed unilaterally in T3.
- **App bar sub-text left alone as instructed**: `onBrandMuted` on
  `brandSurface` measures **4.22:1**. Flagged for Hasan as a brand decision.
- **Material Icons glyphs do not render in `flutter test`**, so icons appear
  as empty boxes in the goldens. The icon font is not loaded by the test
  harness; it is bundled correctly in real builds (`uses-material-design:
  true`, and the tree-shaken font appears in `build/web`). The goldens are
  therefore evidence of colour, layout and type, not of icon shapes.

- **WCAG AA contrast: several spec token pairs fall below 4.5:1, one badly.**
  Measured from the actual token values (not estimated). Worst case is the
  Overline primitive in light mode: `textMuted #A8A8A0` on
  `surface #FFFFFF` = **2.39:1**, against the 4.5:1 AA requirement for
  normal-size text (12px is not "large" under WCAG — large is 24px, or
  18.66px bold). Overline appears on every composed screen. Also below
  4.5:1: the primary button label (`onPrimary` on `primaryAction`,
  **4.26:1**, both modes), ghost/secondary button labels (`primaryAction`
  on `page`/`surface`, **3.88–4.26:1**), the Present pill in light
  (**4.45:1**), the Late pill in light (**3.73:1**), and the app bar
  sub-text (`onBrandMuted` on `brandSurface`, **4.22:1**). Everything else
  measured passes, and dark mode is generally better than light. NOT
  changed in T2 — these are spec colour values, and altering them is a
  design decision, not an implementation fix. Needs a ruling before the
  pilot given the project's existing accessibility commitments (D-21, the
  44px NFR).

- **Fonts are fetched at runtime over HTTP.** `google_fonts` downloads
  Plus Jakarta Sans on first launch and caches it. For an offline-first
  app targeting low-connectivity institutions in Pakistan, this means the
  first launch on a new device needs a network round-trip before text
  renders in the correct typeface, and a cold install offline falls back
  to the platform font. Bundling the `.ttf` files as pubspec assets fixes
  it and removes the network dependency entirely. Not changed in T1
  because the spec said "via google_fonts" and bundling is a delivery
  decision, not a token decision — surfaced for a call before the pilot.
  This is also why the golden test could not be kept (see HANDOFF T1).

- The native DB seam (`lib/core/db/local_db_native.dart`) uses
  `NativeDatabase.memory()`. Correct for a seam with no tables, but T8's
  offline attendance queue must be PERSISTENT — an in-memory queue loses
  unsynced attendance when the app closes, which defeats the entire
  offline-first design. Log this as a carry-forward requirement for T8,
  not as a blocker.
- The `dart:ffi` check was done by grepping the compiled web bundle for
  the string "dart:ffi". That string would not appear there even if the
  seam were wrong, so the grep proved nothing. The actual proof is that
  `flutter build web` succeeded. Note this so the weak method is not
  reused: verify web-safety by building, not by grepping output.

### T10 — 2026-09-18

- **Admin shell selection reuses `RoleDestinations.forRoles` precedence**
  via `isAdminShell()`. The router does not re-derive role priority; admin +
  teacher still resolves to the teacher shell (D-41 unchanged).
- **B-03 closed as not-a-gap on the current backend.** `classId` /
  `sectionId` filters verified live with a bogus-id control.
- **CSV import is synchronous** → no polling or progress UI.
- **CSV is pasted, not picked** — no `file_picker` dependency added; open
  for the user to decide.
- **Wizard uses the tenant's first campus** — resolved before the form
  opens so a missing campus is a retryable state, not a failure at the last
  step. Multi-campus needs a picker later.
- **D-17 recovery:** after a partial failure the role and login fields are
  locked and the retry skips provisioning, so there is no way to create a
  second account for the same person.

### T11 — 2026-09-18

- **Diary opens from a period**, not a free-standing picker: the backend
  key is section + subject + date and the period already holds both.
- **Edit-first**: look up the entry before typing; PUT if it exists, POST
  if not. A 409 is surfaced as a real error, never swallowed.
- **Diary saves always send every field** — PUT is a verified full replace.
- **Shared diary entries are shown as shared** ("Last saved by X"), matched
  on `authorName` vs the teacher's name from `/api/staff/me`.
- **Student timetable held, not mocked** — no endpoint gives a student
  their section; screens say "not available yet". No name-matching guess.
- **Breaks are not shown to students** and the screen will say so — breaks
  live only in `/timetable/periods`, 403 for students and parents.
- **`LoadFailure.unreachable`** added rather than a new `LoadFailureKind`,
  so existing classifications and T6 tests are untouched.
- **`student1` test account created** (linked to STU-001) — verification
  needs a real student login, as T9 needed `parent1`.

### UI fixes — 2026-09-23

- **Debug banner off** in both MaterialApps: it read as product chrome in
  screenshots and was reported as a bug.
- **Appearance (System / Light / Dark)** in More, persisted per DEVICE via
  `shared_preferences` — there is no backend field for it, and three
  choices rather than a switch because a switch cannot express "follow my
  device", which stays the default.
- **Accounts screen** groups Staff / Students / Parents and answers one
  question per row: has this person got a login? People WITHOUT a login
  sort first (same reasoning as D-15). Parents are assembled per student
  (no list endpoint), so a partial failure warns on the list instead of
  replacing it.
- **Gate screens (orphan / identity error) now offer sign-out.** They
  replace the whole shell, so without it a user was stuck in the account.
- **The phone "More" tab is a real list**, not a placeholder; admin's
  Import and sign-out were unreachable on a phone.
- **Desktop gained a top bar** with the institution name and the sync
  indicator, which had existed only in the mobile app bar.

### T13 Batch A — 2026-09-24

- **`current` academic year is read-only and NOT derived.** Probed both
  ways: a year spanning today came back `false`, an expired year stayed
  `true`. The screen explains who sets it instead of showing a control that
  cannot work (D-19). Open item 8 for Ali.
- **Teaching assignments ship add-only**, with the permanence stated on the
  form BEFORE saving. No edit or delete affordance, not even a disabled
  one — the backend has no route for either.
- **No delete buttons anywhere in Batch A.** Deleting a class with sections
  returns 204 and orphans them; deleting a subject leaves assignments
  pointing at nothing. A success that corrupts data silently is worse than
  no button. Backend integrity bug, raised as open item 12.
- **A 409 does not mean a clash.** This backend answers 409 for validation
  failures too, so `SlotFailure` decides by MESSAGE: the two known clash
  wordings render as clashes, everything else is shown verbatim.
- **Clash copy admits the limit** — it says the teacher or room is busy and
  that the app cannot yet show which class, because the response carries no
  conflicting-slot id (open item 10).
- **Timetable layout:** grid ≥768px, day picker + list below. A 6×8 grid at
  360px is unreadable, and a horizontally scrolling table hides half the
  week. Breaks are a full-width band (school-wide, never hold a slot).
- **Setup is one hub tab, not six**, with each step stating what it needs —
  "Create an academic year first" rather than a screen that fails on open.
- **Sections are grouped client-side**: `?classId=` is ignored by this
  backend (bogus-id control).
- **The live end-to-end test drives the repository, not the widgets.**
  `flutter test` uses a fake clock, so a widget-initiated HTTP call never
  completes; only `runAsync` work reaches the real event loop. Full UI E2E
  would need `integration_test` on a device/browser. Stated in the test.

## T14 Batch B — Finance

### Money

- **Money is integer paisa, never a `double`.** `0.1 + 0.2` is not `0.3` in
  binary floating point, and a fee module that drifts by a rupee between a
  receipt and a ledger is not trusted again. `Money` holds an `int` and its
  only entry point is a decimal-string scanner. A test asserts the file's
  own source contains no `double`, `num` or `toDouble` — the absence IS the
  property.
- **The raw response text is rewritten before decoding.** The fee API sends
  money as bare JSON numbers (`5500.00`), and `jsonDecode` turns those into
  doubles before any of our code runs — no reviver sees the literal. So
  `FinanceJson.quoteMoney` quotes the known money keys in the response text,
  the repository asks dio for `ResponseType.plain`, and money reaches the app
  as a String. A key missed from that set does NOT silently become a double:
  `Money.fromJson` throws when handed a number.
- **`total` is overloaded by the backend** — a plan's money total and a
  generation run's invoice COUNT. The key stays in the money set (dropping it
  would put a real amount through a double) and `GenerationResult` reads
  either form. Caught by a widget test, pinned by a unit test.
- **No total is ever computed client-side where the server provides one.**
  Invoice totals, plan totals and both reports are rendered as sent. The one
  arithmetic in the app is `total - paid`, exact in paisa. A test proves the
  server total wins over a deliberately disagreeing line sum.
- **A third decimal is refused on input.** The server rounds `1.005` to
  `1.01`; accepting it would mean showing a number it did not store.
- **Display is always `PKR 12,500.00`** — grouped, two decimals. No new type
  style was needed: every style in the scale is already tabular.

### What the API forced

- **No corrections anywhere.** An approved payment has no void, reverse or
  delete, and cannot even be read by id afterwards; invoices have no edit,
  cancel or delete. ADR-0008 and D-19 agree: no edit affordance ships.
- **No payment date field.** `receivedAt`, `paidAt`, `paymentDate` and `date`
  are all silently ignored. Rather than a control that does nothing, the
  screen states the payment is dated when recorded. Open item 15.
- **No payment history per invoice.** Only a running `paid_amount` exists.
  The detail screen says so, so an empty list is never mistaken for "nobody
  has paid".
- **Only cash and bank transfer.** `source` 400s on anything else, so no
  cheque, card or online chip is offered, and the screen says why.
- **No receipt PDF and no receipt list.** No download affordance; the receipt
  is reachable only at the moment it is issued, which is stated.
- **The collection report takes no filters** — it accepts `period` and
  `academicYearId` and ignores both (`period=1999-01` returned identical
  figures). The screen states its all-time, whole-school scope instead. And
  no monthly chart: the data has no monthly dimension to draw.
- **No section filter on invoices** — `?sectionId=` is ignored (bogus-id
  control). Only class, status and period are offered, each verified.
- **409 again does not mean conflict** — `/fee/heads` and `/fee/plans` answer
  409 for missing fields. The backend's own message is shown verbatim rather
  than a guess at "that already exists".
- **`idempotencyKey` must be a UUID**, and a non-UUID answers "Malformed
  request body", which points at the wrong problem entirely. The repository
  generates one per payment.

### Screens

- **Generation states what it will do before it does it** — which plan,
  which class, which period — and that it cannot be undone, because there is
  no invoice delete. It also states that a repeat run SKIPS rather than
  duplicates, verified live, because that changes how carefully the admin has
  to tread. It deliberately does **not** estimate a student count: there is no
  dry run, and a guess presented as a fact about money is worse than no
  number. The exact result is shown afterwards.
- **Recording and approving are separate surfaces**, because they are often
  separate people. Both say the money is not counted until approved.
- **Defaulters is a worklist**, sorted by largest outstanding with longest
  overdue breaking ties (D-15's principle applied to money), and the amount
  leads the row because it is what the decision turns on.
- **Two pill statuses were added to `StatusPill`** rather than a one-off
  badge: `unpaid` (neutral — an unpaid invoice is the normal state of a fee
  the day it is issued; a wall of red trains people to ignore the colour) and
  `paid`. `partial` was reused. There is no `overdue` variant because the
  backend has no overdue status — it is derived from the due date and said in
  words beside the pill. Goldens regenerated; both pairings added to the
  contrast suite.
- **The year is always passed explicitly.** The backend's `current` flag
  points at an EXPIRED year on live data, so anything resolving the year
  server-side would bill against last year and look plausible doing it. Fee
  plans store the year they are given; the hub names it.
- **Finance is one hub tab**, reusing the Setup hub's `StepRow`, `CreatePanel`
  and `SetupScaffold` rather than a parallel set of components.


## Standing rule — missing backend capability (from T15, applies retroactively)

When a screen needs something the backend does not provide, **ship the
screen with an inline placeholder naming the limitation.** Do not hold the
screen, do not hide the control, never a disabled button with no
explanation, never a silent omission, never a fabricated affordance (D-19).

The placeholder states what is unavailable and why, **in the user's terms** —
"Teaching assignments cannot be changed yet", not "PUT /api/teaching-
assignments returns 404".

Every one of these is kept in **HANDOFF.md § 4a** as a single running list,
and goes to Ali as **one consolidated message at the end of the frontend
work**, not as each is found.

### The narrow exception — blocked actions, not placeholders

A placeholder is correct when a feature is **missing**. It is wrong when the
backend is **silently returning wrong data**, because then the screen looks
fine and the note has nothing to attach to.

The live case is the current academic year: a year spanning today reports
`current: false` while an expired year reports `current: true`.

- Where that affects a **write**, block the action and explain it — do not
  annotate it. An action that silently records against last year's roll is
  worse than one that refuses.
- Where it affects only a **read**, a placeholder naming the scope is enough.

Applied so far: the app never lets the server resolve an academic year. It
is always passed explicitly, and the screen that writes names the year it
used. Recorded as B1 in HANDOFF.md § 4a.


## T15 Batch C — Academic loop

### Marks are numbers, and numbers drift

- **Marks, percentages and grade points are integer hundredths**, never a
  `double` — the same treatment as money, for the same reason. A mark that
  renders as `17.999999` on a report card is the same class of defect as a
  rupee of drift in a ledger. `Marks` has its own scanner and a test asserts
  the file's source contains no `double`.
- **`Marks` is deliberately not `Money`.** Same idea, different unit and
  different job: money always shows two decimals and a currency, a mark
  shows `85` rather than `PKR 85.00`. They are kept apart because neither
  feature should depend on the other and `lib/core/` is limited to
  `{theme, network, db, router, widgets}`. Flagged for extraction if a third
  feature ever needs it.
- **Nothing is computed client-side where the server provides it.** A mark
  POST returns the whole recomputed result — total, percentage, grade, grade
  point, position, pass/fail — so the app renders it. Syllabus progress is
  the server's percentage too; the brief assumed it was not, and it is. The
  only exception is the progress BAR's width, which is a pixel measurement,
  not a number anyone reads.

### What the API forced

- **Two of the batch's eight screens have no backend at all** — grade
  schemes/bands and subject resources. Both still ship, as screens that name
  the limitation, because the standing rule is to state the gap rather than
  hide the control. Neither has a form that cannot save.
- **Grade bands are validated but not wired.** `validateBands` rejects gaps
  and overlaps, and is tested, because the rule is the whole point of the
  feature — a gap means a student scoring in it gets no grade, and that
  surfaces at result time, far from the cause. It is unreachable from any
  screen until an endpoint exists, and that is stated rather than disguised.
- **Papers cannot be listed back**, and re-creating one answers 409 *without*
  returning the existing id. So a paper's id exists only at the moment of
  creation: the papers screen holds the session's papers, offers "Enter
  marks" on each, and warns up front that leaving loses them. The sharpest
  limitation in the batch.
- **Marks cannot be read back either**, so the entry screen always starts
  empty and says so — a teacher must not think an already-marked class is
  unmarked.
- **Publishing locks marks permanently** and there is no unpublish, so it is
  a deliberate confirmed action that states both facts. Before publishing,
  re-posting a mark updates it, so corrections ARE possible — unlike fees.
- **The report card has no file.** Re-verified: `{generatedAt, available,
  status}` and 404 on every file path. No download button, and no print
  button that would only print the browser's chrome.
- **Exam creation takes the academic year explicitly**, so the current-year
  bug does not apply and creation is NOT blocked. The year is passed, never
  resolved.
- **Only the six accepted `term` values are offered**; an unlisted one
  answers a 400 that does not even name the field.

### The remarks privacy call

`isParentVisible` is enforced server-side **for parents** — verified with a
parent token, which also cannot reach another child's remarks. So the screen
ships rather than being blocked.

But a **student token can read any student's remarks, including ones flagged
false** — no visibility filter and no ownership check on that path. That is
a broken access-control defect, raised as open item 23 and the top item for
Ali.

Consequences, deliberately chosen:

- the copy says **"not shown to parents"** and never "private", "staff only"
  or "only you can see this", because none of those is true today and a
  teacher who believed them could be badly caught out. A test asserts those
  words are absent;
- the consequence sits **next to the control**, spelled out for both states,
  not in a tooltip;
- **nothing is filtered client-side** — that would hide a server defect
  behind a screen that looks correct;
- **no student-facing remarks surface is built** until it is fixed.

### A bug the live test caught

`markCoverage` was missing the REQUIRED `clientUuid`. The manual probe had
happened to send one, so only the end-to-end run against the real backend
found it — the case for keeping that test.

### A bug found while building

`mapDioError` reads a response's `message` only when the body is already a
Map, but the finance and academics repositories ask dio for
`ResponseType.plain` (which is what keeps money and marks away from
`jsonDecode`'s number parser). So every server message on a read path was
being silently replaced by a generic fallback. Both repositories now decode
the error body before mapping it. This affected T14 as shipped.


## Auth — a dead token must never become a lockout (fixed 2026-09-25)

Found in use, reproduced against the live backend, and fixed the same day.

**Symptom.** The login screen showed `Access token missing or invalid`
before the user had done anything wrong, and the correct password would not
work.

**Cause, in two parts.**

1. `AuthInterceptor.onRequest` attached the stored bearer token to *every*
   outgoing request — including `POST /auth/login`, which exists precisely
   to obtain a token and is therefore reached when the stored one is dead.
   The backend checks the header at the gate, so the login handler never
   ran and the 401 named the wrong problem.
2. Nothing ever cleared a rejected token. `AuthState.restore()` treats a
   dead session as signed-out but leaves the token in storage, so every
   later attempt re-sent it. Signing out would have cleared it, but signing
   out requires being signed in — so the user was stuck with no way out but
   clearing site data.

Verified live, same credentials in all three cases:

| Request | Answer |
|---|---|
| no `Authorization` header | **200**, signed in |
| stale `Authorization` header | 401 `"Access token missing or invalid"` |
| wrong password, no header | 401 `"Invalid credentials"` |

**Fix.**

- `AuthInterceptor.unauthenticatedPaths` — `/auth/login` and `/auth/refresh`
  never carry a bearer token, and any header a caller set is stripped.
  `/auth/logout` is deliberately excluded from that set: it authenticates
  the session it is ending.
- On a 401 that cannot be recovered — no refresh token, or refresh itself
  failed — local tokens are cleared. **Only on a real 401 from the server**,
  never on a network failure, so a flaky connection at startup does not sign
  a user out.

Nine tests in `network_test.dart` pin both halves, including the two
negatives (a recoverable expiry keeps the session; a connection error keeps
it too). Reverting either half turns five of them red — checked.

**Why this was worth more than a patch.** The failure mode was a hard
lockout with a message that pointed at the wrong thing, on the one screen a
user cannot work around. It was also latent for every earlier task — any
backend restart could trigger it.

## Motion implemented (2026-09-25) — D-03 / D-04 / D-05 / D-29

Motion was decided with the visuals and never built. This implements the
existing decisions; **nothing here is a new visual decision.** Where a
moment is not named in D-29, it did not get motion.

`lib/core/theme/motion.dart` (`AppMotion`) holds every duration and curve,
transcribed from D-29: login 400, hero 300, checklist tick 300, KPI 250,
confirmation 250, empty state 250, section 200, stagger step 60, hero scale
0.97, functional band 120–180 (D-04). Curves: functional ease-out,
expressive entrance `cubic-bezier(.2,.9,.3,1)`, expressive settle
`cubic-bezier(.2,1.3,.4,1)`.

`lib/core/widgets/motion_reveal.dart` has the only two motion widgets:

- **`MotionReveal`** — a one-shot arrival: fade, optional rise or scale.
  Drives `Opacity` and `Transform` ONLY, so no frame costs a layout pass
  (D-05). No `repeat`, no `reverse`, by construction.
- **`MotionConfirm`** — the submit-confirmation settle, and the **only**
  call site of the overshoot curve. Kept separate so `expressiveSettle`
  cannot quietly spread; a test asserts it is used exactly once.

Wired to the moments D-29 names, and no others: empty/error/offline state
entrance (on the shared `StateFrame`, so every state arrives identically),
admin KPI stagger, section rows, onboarding checklist, hub `StepRow` (its
own `number` IS the stagger index, so a new step cannot forget to join the
sequence), the parent status card, and the marks-saved and
invoices-generated confirmations.

**Not wired, deliberately:** tab switching, which D-29 prohibits outright —
a surface switched dozens of times a day should be instant, and animating
it would also fight `IndexedStack`'s keep-alive (D-30). A test asserts the
shell contains no `AnimatedSwitcher`/`PageView`/`TabBarView`.

**Stagger is capped at six steps.** Uncapped, item 40 of a roster would
start 2.4s in and the screen would read as broken rather than considered.

**Reduced motion** drops scale and travel and keeps the opacity fade,
exactly as D-29 requires. Tested in both widgets.

### Two things this turned up

- **`check_tokens.sh` did not cover durations**, so the new token layer
  would not have been enforced. Added `PATTERN_MOTION_DURATION`: a bare
  millisecond literal outside `lib/core/theme` is now a violation. Only
  bare digits are flagged, so a named constant passes — which is why the
  login storyboard's `_Timing` is untouched. Verified with a planted
  negative. The shimmer period moved into `AppMotion.shimmerPeriod`.
- **`MotionConfirm` had a latent crash**, caught by the test that mounts it
  with `show: false`: a lazy `late final` controller was first initialised
  inside `dispose()`, constructing a ticker against a deactivated element.
  Both widgets now create their controller eagerly in `initState`.

### Known discrepancy, not fixed

D-29 says "login entry 400ms". The shipped login intro is a **2800ms**
multi-phase storyboard (`_Timing` in `login_screen.dart`) with a deliberate
one-second hold. It predates this work, is carefully built, and honours
reduced motion. Changing it to 400ms would destroy it; changing the
decision is a conversation. Flagged rather than silently reconciled.

## T16 Batch D — Operations, and six carried decisions

### The six rulings, as applied

- **D-29 amended, not violated.** The login intro stays at **2800ms**.
  D-29's "400ms" predates the intro; D-04's budget rule assumes animation
  costs the user time, and here it does not — the form is laid out and
  focusable from the first frame, nothing is gated on the animation, and
  `login_polish_test.dart` already proves typing lands early. Recorded so
  nobody later "fixes" it to 400ms.
- **`Marks` and `Money` stay separate.** They resemble each other
  coincidentally — different units, formatting and validation. Duplication
  beats a wrong abstraction.
- **D-27 amended for admin only.** Nine destinations turned More into a
  second navigation surface, which is exactly what D-27 exists to prevent.
  Admin gets a drawer below 600px via `AppShell.usePhoneDrawer`; teacher,
  parent and student keep the bottom bar unchanged. Nothing is truncated in
  the drawer, so no destination can be unreachable — the T10 failure.
- **`file_picker` ships.** The file is read into the SAME text field the
  paste path uses, so the existing header guard and every existing test
  cover both routes rather than the file path being a second, unchecked way
  in. `readAsBytes`, not a path: the web build has none.
- **`integration_test` is set up**, scoped to three steps — sign in, load a
  screen, perform a write. See the honesty note below.
- **Multi-campus picker: not now.** Single-campus pilot.

### What the backend got RIGHT here

Worth recording, because T15's remarks did not. Verified with real tokens
per role: internal comments are filtered server-side for a complainant; a
complainant's `isInternal: true` is **downgraded** by the server; an
anonymous complaint stores no `raised_by_user_id` at all, so the admin's own
detail view has nothing to leak; and cross-user reads are 404/403. The
internal-comment feature therefore **ships** — the UI labels a guarantee
rather than creating one, and nothing is filtered on the device.

### What the backend did not

- **Notifications carry no target.** `data` is null on every row and there
  is no subject id, so a notification cannot be opened onto the thing it is
  about. No tap-through ships; the screen says so once, at the top.
- **No notification preferences endpoint** — per-category toggles cannot
  ship.
- 🔴 **A parent cannot raise a complaint at all.** `POST /api/complaints`
  requires `campusId`, the server will not default it, and **no endpoint a
  parent may call carries one** (`/api/campuses` is 403; `/api/guardians/me`
  and `/api/institution/me` have none). Teacher and student resolve it from
  `/api/staff/me` and `/api/students/me`. `resolveCampusId()` returns null
  for a parent and the screen explains it rather than offering a form that
  cannot submit. Open item 39.
- **Staff attendance has its own vocabulary** — `half_day`, and no
  `excused`; students the reverse. Four of five values are shared, which is
  exactly why one enum would have compiled and then sent an invalid status.
  `AppStatus.halfDay` was added to the pill with letter `H` on a half-filled
  circle: D-21 requires the (shape + letter) PAIR to be unique, not the
  shape, and Present/Leave already share one. The distinguishability test
  now asserts against the number of statuses rather than a literal, so a
  seventh cannot pass by bumping a magic number.

### The bell finally does something

`MobileAppBar` has had an unused `onNotificationsTap` since T5. It is wired
to the notifications destination where the role has one, and returns null
where it does not — so no bell renders rather than one that goes nowhere.
The bar is a plain Container, not a Material `AppBar`, so the drawer also
needed an explicit menu button: without it a drawer opens only by edge
swipe, which is undiscoverable and unusable with a screen reader.

### Honesty note — `integration_test` is written but NOT yet run

The file exists, analyzes clean, and is scoped as agreed. **It has not been
executed**, because this machine has no way to: there is no Windows desktop
project configured, no Android device or emulator attached, and web
integration tests need `chromedriver`, which is not installed. Running it is
one command once chromedriver is on the machine — see HANDOFF.md. Claiming
the gate item green without a run would have been the easy lie.

## Polish pass (2026-09-27) — consistency, not features

Scope was existing screens only. **No new data, no new endpoints, no
placeholder became a working control.** 661 tests green in, 671 green out.

### What changed

- **Sidebar and drawer grouped.** `NavDestination.group` is optional and
  purely presentational; the sidebar groups by FIRST APPEARANCE rather than
  sorting, so `selectedIndex` still indexes into the caller's own list. The
  admin groups — Overview, School, Operations, People — mirror the hubs the
  product already has, so the nav and the screens describe one shape. The
  phone drawer got the same treatment from the same shared `startsGroup`,
  because grouping one and not the other is the drift this pass exists to
  remove. Headings are suppressed in the 72px compact rail, which has no
  room for a label. Active state is unchanged: still a left border, never a
  fill (D-22).
- **Admin dashboard.** Gained the title + one-line subtitle every hub has
  and it alone lacked. The KPI row stacks below `tableCollapseBreakpoint`
  instead of cramming three equal columns at 360px with a large text scale.
  The section heading now **follows the data**: the list holds every
  section, not just unfinished ones, so "Sections needing attention" was
  simply untrue when nothing was — it now reads "All sections / Every
  section is set up", and otherwise counts what is unfinished. Renamed from
  "Sections" after a test caught it colliding with the KPI card's own label.
- **Empty-state copy.** Eight screens said "Nothing could be loaded.",
  "Nothing to show", "No diary" or "Not available" — dead ends that name
  nothing and offer nothing, written across four batches. They now follow
  the house voice the other thirty already used: name what is absent, say
  what appears there or what to do. "Reopen this tab to try again" is the
  phrasing already in the product, not a new one.
- **One name for the backend.** "the system" → "this system" in three
  places. "the app" is kept only where the limitation really is the app's
  (it cannot discover a parent's campus), because that distinction is
  useful rather than accidental.

### What did NOT change, deliberately

- **The three hubs were already identical** — same title/subtitle
  structure, same vertical rhythm, same shared `StepRow`. Nothing to fix,
  so nothing was touched.
- **Section rows still show one next action, not every gap.**
  `nextAction` is deliberately the single most important missing thing in
  dependency order (D-19 + D-15's reasoning). Listing all three booleans
  would have been noise, and would have contradicted a decision already
  made.
- **No analytics, no charts, no owner dashboard.** There is no analytics
  backend and no schema. A chart now would display invented numbers, which
  would undo the one property 27 on-screen placeholders were written to
  protect. If it is wanted, it is a request to Ali first.

### Goldens: regenerated NONE, and why

The shell gallery's destinations carry no `group`, so an ungrouped list
renders byte-identically — that backward compatibility is the property the
grouping was designed around, and the untouched shell goldens demonstrate
it rather than merely asserting it. A test pins it directly.

### `check_tokens.sh` had a hole, found by planting a negative

The single-line `EdgeInsets` pattern is grep-based, so a value on a
FOLLOWING line was invisible — and `EdgeInsets.fromLTRB(` spread over five
lines is the house style. A planted `23` passed clean, which is how the gap
surfaced. Added `check_multiline_edgeinsets`, modelled on the
`check_multiline_sizedbox` helper the script already had for exactly this
problem with a different constructor.

It immediately found **two real violations** in T15/T16 code: a bare `0` in
a multi-line `fromLTRB`. Rather than exempting zero — an exception everyone
would have to remember — `AppSpacing.none` was added. It is deliberately
excluded from `AppSpacing.all` and the gallery, because it is the absence
of a step, not a step. `EdgeInsets.zero` remains right when every side is
zero.
