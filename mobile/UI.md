# UI.md — huddle · League & Club App (NaSCon '26, Part I)

The single source of truth for every screen in `mobile/`. Every colour, font size, spacing value, button, animation and message in the app comes from this file. If a screen needs something not listed here, add it here first, then build it.

Platform brand: **huddle** ("Every club, one league home."). Design direction: **"Clean Light"** as the default, with a matching **dark mode** built from the same tokens.

---

## 0. Brand: huddle, and who owns which logo

### 0.1 Three levels of identity

| Level | Whose | Where it appears | Required by spec? |
|---|---|---|---|
| **Platform** | huddle (our app) | Launcher icon, splash screen, login footer "powered by huddle", About screen | No, our product brand |
| **Tenant** (white-label) | Alpha Sports, Beta Athletics | App bar logo + name on every screen, brand colour of the whole theme, login header after server/tenant is known, receipt PDF header | **Yes.** FR-2.1: tenant has logo, colours, name; §8.6 area 2: "The tenant's logo and colors are applied" |
| **Club** (team) | Alpha FC, Alpha Rovers… | Crest on club profile, fixture rows, match header, standings rows | Not required. Clubs have profiles (venue, socials, stats, roster, staff), but the spec asks for no club logo. We show an auto-generated crest (see 0.4) |

Rule: inside the app, the **tenant** leads. huddle never appears in the app bar.

### 0.2 The huddle mark

Six club dots around one larger centre ball. Built from circles only, so it is easy to draw in Flutter (`CustomPainter`) or ship as one SVG/PNG.

```text
viewBox 0 0 48 48
centre ball   circle cx 24  cy 24  r 7     colour: accent (CTA)
club dots     r 4.5 at (39,24) (31.5,37) (16.5,37) (9,24) (16.5,11) (31.5,11)   colour: brand
```

| Variant | Ball | Dots | Background |
|---|---|---|---|
| Light (default) | `#C2410C` | `#1D4ED8` | `#F4F6F8` / white |
| Dark | `#FB923C` | `#8AB4FF` | `#0B1220` |
| Monochrome (Android 13 themed icon) | one colour | same colour | system |
| On a tenant colour | `#FDBA74` | `#FFFFFF` | tenant brand |

Wordmark: **huddle**, always lowercase, Manrope 800, letter-spacing −0.02em, text colour (`#121A23` light / `#E8EDF3` dark). Lock-up = mark + 12 px gap + wordmark, mark height = 1.3× cap height.
Clear space around the mark = half its width. Never recolour the dots individually, stretch, rotate, outline or add shadows.

### 0.3 Platform assets to produce

| Asset | Spec | File |
|---|---|---|
| Launcher icon (adaptive) | Foreground: mark at 66% of the 108 dp canvas, centred. Background: `#FFF7ED` (warm cream, 1 px `#FED7AA` edge in previews) | `android/app/src/main/res/mipmap-*` + `mipmap-anydpi-v26/ic_launcher.xml` |
| Themed (monochrome) icon | Mark in one colour, transparent background | `ic_launcher_monochrome` in the adaptive icon XML |
| Splash | Background `#FFF7ED` (light) / `#0B1220` (dark), mark 96 dp centred, wordmark under it, then "Loading your league…" in muted text | `android/app/src/main/res/drawable/launch_background.xml` + `values-night/` |
| App name | `huddle` | `android:label` in `AndroidManifest.xml` |
| In-app asset | `assets/brand/huddle_mark.svg` (or a `HuddleMark` CustomPainter: no extra package needed) | `mobile/assets/brand/` |
| Login footer | "powered by" (muted, 13 sp) + 18 dp mark + "huddle" (Manrope 800, 15 sp) | Login screen bottom |

Adding launcher icons without new packages: export the mark as PNG at 48/72/96/144/192 px and drop them into the five `mipmap-*` folders. (`flutter_launcher_icons` works too, but it is an extra pub dependency.)

### 0.4 Tenant logos and club crests

- **Tenant logo:** circle with the tenant's initials (AS / BA), Sora 700, tenant brand background, onBrand text. 32 dp in the app bar, 56 dp on login, 72 dp in About. Comes from the tenant record (`logo_url` if the backend provides one, otherwise the initials fallback). Tenant brand: Alpha `#1D4ED8` / `#8AB4FF` dark, Beta `#0F766E` / `#5EEAD4` dark (§3.3).
- **Club crest (auto-generated):** a shield shape filled with surface2, 2 px tenant-brand outline, club initials (first letters of up to 3 words: "Alpha FC" → "AFC") in Manrope 800. Sizes: 24 dp in lists, 44 dp in match header, 76 dp on club profile. No image upload needed, consistent everywhere, and it can never break offline.
- Every logo/crest is decorative to screen readers when the name is printed next to it; otherwise its Semantics label is the tenant/club name.

---

## 1. What the judges check, and where this file answers it (§8.6)

| Judge area (2 pts each) | What we do | Section |
|---|---|---|
| 1. Navigation & ease of use | 5 labelled bottom tabs; every task ≤ 3 taps; back always works; no dead ends | 9 |
| 2. Visual consistency & hierarchy | One token set, one type scale, one button set; score and Buy/Pay are the strongest elements; tenant logo + colour applied | 3, 4, 5, 6 |
| 3. Feedback & error handling | Loading, success, plain-language errors, always-visible sync strip, confirm before risky actions | 6, 8 |
| 4. Readability & accessibility | Body 16 sp, contrast ≥ 4.5:1 (checked), 48 dp targets, icons with labels, status never by colour alone | 3, 4, 10 |
| 5. Right screen for the right role | Role-gated actions, helpful empty states, works at 360×640 and in landscape | 9, 10 |

---

## 2. Light and dark mode — decision

- The spec neither requires nor forbids dark mode. Judges score contrast, consistency and tenant colours, so dark mode is a small accessibility plus, **not** a requirement.
- Material 3 makes it cheap: one `ThemeData` for light, one for dark, both built from the tokens below. `ThemeMode.system` by default, plus a toggle in **Profile → Appearance: System / Light / Dark** (saved in `shared_preferences`).
- **Rule:** no widget ever uses a raw `Color(...)`. Everything reads `Theme.of(context).colorScheme` or `context.status` (our `ThemeExtension`). That is what makes both modes work automatically.
- **Time box:** if dark mode is not working after 20 minutes, ship light only and remove the toggle. Never demo a half-finished dark mode.
- Demo to judges in **light mode** (projector/sunlight readability); mention dark mode only if asked.

---

## 3. Colour tokens

All pairs below were contrast-checked (WCAG 2.1). Text needs ≥ 4.5:1, input borders and icons ≥ 3:1.

### 3.1 Core roles

| Token | Flutter role | Light | Dark | Used for |
|---|---|---|---|---|
| bg | `surface` (scaffold) | `#F4F6F8` | `#0B1220` | Screen background |
| surface | `surfaceContainerLowest` | `#FFFFFF` | `#131C2B` | Cards, sheets, app bar, nav bar |
| surface2 | `surfaceContainerHigh` | `#F1F5F9` | `#1A2536` | Table headers, chips, close buttons |
| divider | `outlineVariant` | `#E2E7EC` | `#263247` | Hairlines between rows (decorative only) |
| inputBorder | `outline` | `#748297` | `#64748B` | Text field and secondary button borders (3.9:1 / 3.6:1) |
| text | `onSurface` | `#121A23` | `#E8EDF3` | Main text (17.5:1 / 14.5:1) |
| muted | `onSurfaceVariant` | `#4B5866` | `#A3B0BF` | Secondary text, captions (7.3:1 / 7.8:1) |
| brand | `primary` | `#1D4ED8` | `#8AB4FF` | Tenant colour: primary buttons, active tab, links |
| onBrand | `onPrimary` | `#FFFFFF` | `#0B1220` | Text on brand (6.7:1 / 9.0:1) |
| brandSoft | `primaryContainer` | `#E0E7FF` | `#1E2A4A` | Selected chips, active-tab pill, role badge |
| onBrandSoft | `onPrimaryContainer` | `#1E3A8A` | `#C7D7FF` | Text on brandSoft (8.4:1 / 9.8:1) |
| cta | `tertiary` | `#C2410C` | `#FB923C` | **Only** Buy / Pay / LIVE. Nothing else is orange |
| onCta | `onTertiary` | `#FFFFFF` | `#1A0E05` | Text on CTA (5.2:1 / 8.4:1) |

### 3.2 Status colours (`ThemeExtension<StatusColors>`)

Always paired with an icon **and** a word. Colour is never the only signal.

| Status | Light bg / text | Dark bg / text | Icon + label examples |
|---|---|---|---|
| success | `#DCFCE7` / `#14532D` | `#0F2E1D` / `#86EFAC` | ✓ Clinched · ✓ Applied · ✓ Paid · Online |
| warning | `#FEF3C7` / `#78350F` | `#2E230B` / `#FCD34D` | Wi-Fi-off Offline · ⏱ Pending · Last one! · Postponed |
| danger | `#FEE2E2` / `#7F1D1D` | `#3A1414` / `#FCA5A5` | ✕ Eliminated · ✕ Rejected · ⚠ error banners |
| neutral | `#F1F5F9` / `#334155` | `#1A2536` / `#C9D3DC` | ○ Still possible · Disallowed · Done |
| info | brandSoft / onBrandSoft | brandSoft / onBrandSoft | Syncing… · Pending (queue) · role badges |
| live | cta text on surface | cta text on surface | ● LIVE 67' (dot pulses, see §7) |

### 3.3 Tenant (white-label) colours — FR-2.1

The logged-in user's tenant sets `brand` and the logo. Everything else stays the same.

| Tenant | Name | Light brand | Dark brand | Logo |
|---|---|---|---|---|
| tenant-alpha | Alpha Sports | `#1D4ED8` | `#8AB4FF` | "AS" monogram in a circle |
| tenant-beta | Beta Athletics | `#0F766E` (5.5:1 on white) | `#5EEAD4` | "BA" monogram |

Build with `ColorScheme.fromSeed(seedColor: tenantBrand, brightness: …)` and then **override** the roles in §3.1 with the exact values (so contrast stays as checked).

---

## 4. Typography

- **Display/numbers:** Sora (600, 700). **Body/UI:** Manrope (400, 500, 600, 700, 800).
- **Bundle the .ttf files** in `mobile/assets/fonts/` and declare them in `pubspec.yaml`. Do **not** fetch fonts at runtime (the offline desk check runs in airplane mode). If the font files cannot be obtained, fall back to the platform default (Roboto) with the exact same scale; consistency matters more than the typeface.
- Scores, prices and table numbers use `FontFeature.tabularFigures()` so digits don't jump when they change.
- Respect system text size up to 1.3× (`MediaQuery.textScaler`); layouts must not clip at 1.3×.

| Style | Flutter `TextTheme` | Font | Size / line height (sp) | Weight | Used for |
|---|---|---|---|---|---|
| Score XL | `displayMedium` | Sora | 44 / 48 | 700 | Live score on Match detail |
| Title L | `headlineSmall` | Sora | 24 / 32 | 700 | Screen titles ("Fixtures") |
| Title M | `titleLarge` | Sora | 18 / 24 | 700 | Sheet titles, product names |
| Title S | `titleMedium` | Manrope | 16 / 22 | 700 | Card titles, team names (bold) |
| Body | `bodyLarge` | Manrope | 16 / 24 | 400 | Default text, list rows |
| Body S | `bodyMedium` | Manrope | 14 / 20 | 500 | Secondary lines, table cells |
| Label | `labelLarge` | Manrope | 15 / 20 | 800 | Buttons |
| Caption | `bodySmall` | Manrope | 13 / 18 | 600 | Section labels (UPPERCASE, +0.06em), timestamps |
| Badge | `labelSmall` | Manrope | 12 / 16 | 800 | Status chips, nav labels |

Nothing in the app is smaller than 12 sp.

---

## 5. Spacing, shape, size

| Token | Value | Use |
|---|---|---|
| space xs / sm / md | 4 / 8 / 12 | Inside components |
| space lg | 16 | Screen padding, card padding, gaps between cards |
| space xl / 2xl | 24 / 32 | Between sections, sheet padding |
| radius sm | 8 | Chips, badges |
| radius md | 12 | Inputs, small buttons, list groups |
| radius lg | 16 | Cards, primary buttons |
| radius xl | 24 | Bottom-sheet top corners |
| radius full | 999 | Logo, avatars, nav pill |
| touch target | **48 dp minimum** | Every tappable thing; icon buttons are 48×48 |
| button height | 54 (primary), 48 (secondary), 40 (inline row actions, still ≥ 48 wide with padding) | |
| app bar | 56 | Logo + tenant name, or back + title |
| sync strip | 32 (online) / 40 (offline, has "View" action) | Directly below app bar on **every** screen |
| bottom nav | 72 | 5 tabs, icon + text label |
| elevation | Light: 0 + hairline borders; sheets/dialogs `elevation 3`. Dark: no shadows, use surface/surface2 steps | |

---

## 6. Components

### 6.1 Buttons (one set, used everywhere)

| Variant | Light | Dark | When |
|---|---|---|---|
| **CTA** (`FilledButton` styled tertiary) | `#C2410C` bg, white text | `#FB923C` bg, `#1A0E05` text | Buy, Pay, Buy now. **Max one per screen** |
| **Primary** (`FilledButton`) | brand bg, onBrand text | brand bg, onBrand text | Sign in, Confirm transfer, Open receipt, Sync now, + Goal |
| **Secondary** (`OutlinedButton`) | surface bg, 1.5 px inputBorder, text colour | same tokens | Add to cart, Cancel, Change, Discipline |
| **Text** (`TextButton`) | brand text | brand text | View, Change server, Undo in snackbar |
| **Destructive** (`OutlinedButton` danger) | 1.5 px `#991B1B` border + text | `#FCA5A5` border + text | Release player, End match, Undo/compensate |
| **Disabled** | surface2 bg, muted text, label explains why ("Sync now · waiting for connection") | same | Never just greyed without a reason |

States: pressed = 8% overlay (Material default); focused = 2 px brand outline; loading = spinner replaces label, button keeps its width and is disabled (prevents double checkout).

### 6.2 Inputs
`OutlinedInputBorder` radius 12, 1.5 px `inputBorder`; focus 2 px brand; error 2 px danger text colour + message under the field in plain language. Always a visible label above the field (not placeholder-only). Height 52.

### 6.3 Chips / badges
Radius 8, 12 sp weight 800, padding 3×8. Status chips follow §3.2 and always include an icon or symbol (✓ ✕ ○ ⏱ ●) + word.

### 6.4 Cards and list groups
Surface bg, radius 16, 1 px divider border (light) / no border, surface step (dark). Rows inside groups separated by 1 px divider. Row min height 56.

### 6.5 Sync strip (always visible — NFR-4, judge area 3)

| State | Colours | Text | Action |
|---|---|---|---|
| Online | success | ✓ Online · all changes synced | — |
| Offline | warning | Wi-Fi-off Offline · N actions waiting | **View** → Sync screen |
| Syncing | info | ↻ Syncing N actions… (icon rotates) | — |
| Sync finished with rejects | danger | ✕ 1 action not applied | **View** |

It is a `Semantics(liveRegion: true)` so screen readers announce changes.

### 6.6 Bottom navigation
5 tabs, always icon **and** label: **Fixtures · Standings · Store · Club · Profile**. Active = brand colour + brandSoft pill behind the icon + bold label + `aria-current`. Every role sees the same 5 tabs; role-only tools appear inside screens (§9).

### 6.7 Feedback widgets
- **Snackbar:** bottom, dark slate bg in both modes (`#121A23` light / `#E8EDF3` dark with inverse text), success icon, optional Undo text button, 4 s.
- **Confirmation (risky actions):** modal bottom sheet with what will happen, a reason field when relevant, Cancel (secondary) + action button. Used for: compensate/disallow event, end match, release player, transfer, loan, checkout over PKR 0.
- **Loading:** skeleton rows (surface2 blocks, pulsing opacity 0.5↔1.0, 1 s) for lists; button spinner for actions. Never a blank screen.
- **Empty:** icon + one sentence + action. "No matches yet. Fixtures appear here when the league organiser publishes them." / "Your cart is empty. Browse the club store." / "Nothing waiting. You're all caught up."
- **Error:** inline danger banner, plain language + what to do + Retry. Never show raw codes, stack traces or "Error 500".

### 6.8 Domain components
- **Score:** Sora 44 tabular, `2 : 1`, LIVE chip under it. Strongest element on Match detail.
- **Price:** always `PKR 4500.00` (minor units ÷ 100, two decimals, no thousands separator, matches the receipt).
- **Standings row:** rank, team, P, GD, PTS (bold) + status chip under the team; brand left border for qualifying spots; dashed divider at the qualification cut-off.
- **Timeline row:** minute (bold), event; compensated events are struck through **and** carry a "Disallowed" chip.

---

## 7. Motion

All motion is short and purposeful. If `MediaQuery.disableAnimationsOf(context)` is true, every duration becomes 0 (except the live dot, which becomes a static dot).

| Token | Duration | Curve | Use |
|---|---|---|---|
| fast | 150 ms | `Curves.easeOut` | Button press, chip select, toggle |
| medium | 250 ms | `Curves.easeOutCubic` | Score change, list item insert, snackbar |
| slow | 350 ms | `Curves.easeInOutCubicEmphasized` | Page transitions, bottom sheets |

| Animation | How (Flutter built-ins only) |
|---|---|
| Page transitions | Default Material 3 `ZoomPageTransitionsBuilder` (Android); back gesture works |
| Tab switch | `AnimatedSwitcher` fade, medium |
| Score changes | `AnimatedSwitcher` on the score text: fade + scale 0.8→1.0, medium; brief brandSoft flash behind it |
| LIVE dot | `FadeTransition` 1.0↔0.35, 1200 ms, repeat |
| New timeline event | `SizeTransition` + fade on insert, medium |
| Sync strip state change | `AnimatedContainer` colour/height, medium; ↻ icon `RotationTransition` while syncing |
| Pending → applied | Chip cross-fades from "⏱ Pending" to "✓ Applied", then row slides out after 1.5 s |
| Bottom sheets | `showModalBottomSheet` default (slow) |
| Variant select | `AnimatedContainer` border 1.5→2.5 px + soft fill, fast |
| Loading skeleton | Opacity pulse 0.5↔1.0, 1000 ms |
| Pinned product appears (realtime) | Slide up 16 px + fade, medium |

No parallax, no confetti, no motion longer than 400 ms.

---

## 8. Copy: plain-language messages for API error codes

Map every backend `error.code` to a sentence. Show the sentence, never the code. (Codes from Appendix B.)

| Code | Message shown to the user |
|---|---|
| UNAUTHENTICATED | Your session has ended. Please sign in again. |
| FORBIDDEN | You don't have permission to do this with your role. |
| VALIDATION_ERROR | Some details are missing or invalid. Check the highlighted fields. |
| OUT_OF_STOCK | Sorry, this size just sold out. Try another size. |
| PAYMENT_DECLINED | Your payment was declined. No money was taken. Try another card. |
| PAYMENT_CAPTURE_FAILED | We couldn't complete the payment. No money was taken. Please try again. |
| INVALID_DISCOUNT_CODE | That discount code isn't valid. |
| MATCH_NOT_IN_PROGRESS | This match isn't live, so scores can't be added. |
| ILLEGAL_TRANSITION | This match can't move to that status from where it is now. |
| TIE_NOT_ALLOWED | This sport doesn't allow a draw. Record a tie-break winner first. |
| INVALID_COMPENSATION | That event was already corrected or can't be corrected. |
| INNINGS_COMPLETE / SERIES_ALREADY_DECIDED | This team's innings / the series is already finished. |
| TRANSFER_WINDOW_CLOSED | The transfer window is closed on that date. |
| SQUAD_FULL | The destination squad is full. |
| MIN_POSITION_VIOLATION | This move would leave the squad without enough players in that position. |
| PLAYER_ON_LOAN | This player is on loan and can't be moved until the loan ends. |
| NOT_IN_SQUAD | This player isn't in that squad anymore. |
| CROSS_TENANT_TRANSFER | Players can only move between clubs in the same organisation. |
| INVALID_BASE_VERSION | This change is out of date. Refresh and try again. |
| RATE_LIMITED | Too many requests. Please wait a few seconds. |
| any 5xx / network | We couldn't reach the server. Your changes are saved and will sync when you're back online. |

Voice: short, friendly, says what happened and what to do next. Sentence case. "Club manager", not "CLUB_MANAGER".

---

## 9. Navigation and roles

```
Login ──► Fixtures (home for every role)
Tabs:  Fixtures │ Standings │ Store │ Club │ Profile
Fixtures ─► Match detail ─► (Organizer) Score entry ─► confirm sheet
                         └► Pinned product ─► Store variant sheet
Standings ─► Head-to-head ─► Match detail
Store ─► Product sheet (variant, discount) ─► Pay ─► Receipt (view / download PDF)
Club ─► Club profile (Roster · Staff · History) ─► (Manager) Player ─► Transfer / Loan / Release
Profile ─► Sync queue · Appearance (System/Light/Dark) · Server address · Sign out
Sync strip "View" ─► Sync queue (from any screen)
```

| Role | Extra things they see | Hidden for them |
|---|---|---|
| Viewer | Read-only everything + Store | All edit buttons |
| Player | + "My profile" card in Profile | All edit buttons |
| Club Manager | + "Manage" on **own** club roster, player actions | Score entry, other clubs' edit buttons |
| League Organizer | + "Score entry" on **own** league's live matches | Roster editing |
| Super Admin | Everything | — |

Rules: role badge in the app bar on every screen; hidden means not rendered (not just disabled); back button/gesture always returns to the previous screen; deep screens show a back arrow with an `aria-label`/`Semantics` label.

---

## 10. Layout, responsiveness, accessibility

- Design width 360 dp (minimum, judges test 360×640). Every screen scrolls (`ListView`/`CustomScrollView`); no fixed heights that can overflow.
- **Rotation:** landscape keeps the same layout inside a centered `ConstrainedBox(maxWidth: 600)`; nothing overflows.
- Text scale 1.3× must not clip: use `Flexible`, `Wrap`, `maxLines` + ellipsis on team names.
- Every icon-only button has a tooltip + Semantics label. Decorative icons are excluded from semantics.
- Every widget a test or judge touches gets `Semantics(identifier: 'snake_case_id')` (Appium) and a readable label.
- Status uses icon + word + colour; links are underlined or clearly buttons.
- Checked contrast: all text pairs in §3 ≥ 5.2:1; borders ≥ 3.5:1.

---

## 11. Flutter implementation

```
mobile/lib/core/theme/
  tokens.dart        all hex values from §3, both modes; spacing/radius/durations from §5 and §7
  status_colors.dart ThemeExtension<StatusColors> (success, warning, danger, neutral, info) with lerp
  typography.dart    TextTheme from §4 (Sora + Manrope, tabular figures helper)
  app_theme.dart     buildTheme(Brightness, Tenant) → ThemeData: colorScheme overrides, filled/outlined/text
                     button themes, inputDecorationTheme, chipTheme, navigationBarTheme, bottomSheetTheme,
                     snackBarTheme, cardTheme, pageTransitionsTheme
  tenant.dart        tenant-alpha / tenant-beta brand colours + logo initials
mobile/lib/core/brand/
  huddle_mark.dart   HuddleMark(size, variant) CustomPainter from §0.2 (light, dark, mono, onBrand)
  tenant_logo.dart   TenantLogo(tenant, size): initials circle in tenant brand colour
  club_crest.dart    ClubCrest(name, size): shield + initials, tenant-brand outline
mobile/lib/core/widgets/
  sync_strip.dart  status_chip.dart  app_button.dart  empty_state.dart  error_banner.dart
  skeleton.dart  confirm_sheet.dart  score_text.dart  price_text.dart  role_badge.dart
mobile/lib/core/copy/error_messages.dart   the table in §8
```

`MaterialApp(theme: buildTheme(Brightness.light, tenant), darkTheme: buildTheme(Brightness.dark, tenant), themeMode: settings.themeMode)`.

**Rule for Claude Code:** screens may only use `Theme.of(context)`, `context.status`, `AppSpace`, `AppRadius`, `AppMotion` and the shared widgets above. Any raw colour, font size or padding number in `features/` is a bug.

---

## 12. Pre-judging checklist (before 15:15)

- [ ] Login with all 5 demo accounts; role badge correct; role-only tools only where allowed
- [ ] Task A: Standings → open a match in ≤ 3 taps; live score updates
- [ ] Task B: Store → size → Pay → receipt opens; price shows PKR 4500.00 style
- [ ] Task C: Manager roster action; repeat in airplane mode; force-close; reopen; queue still there; reconnect; per-action result in plain words; queue clears
- [ ] Sync strip visible on every screen in all 3 states
- [ ] Every list has an empty state; every action has loading + success/error feedback
- [ ] Confirm sheet before release / compensate / end match / pay
- [ ] 360×640 and landscape: no overflow stripes; text scale 1.3× OK
- [ ] Tenant logo + brand colour visible on every screen; tenant-beta login shows teal
- [ ] Launcher icon and app name show **huddle**; splash shows the mark; login footer says "powered by huddle"
- [ ] Club crests render from initials on fixtures, match header, standings and club profile
- [ ] Light mode (and dark, if shipped) checked on the real phone, brightness at 50%
- [ ] Release APK at `mobile/release/app-release.apk`, server address editable in Profile/Login
