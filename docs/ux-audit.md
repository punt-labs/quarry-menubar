# Quarry Menu Bar — UX/UI Audit

**Date**: 2026-02-14
**Version audited**: 0.1.0
**Platform**: macOS 14+ (Sonoma), MenuBarExtra(.window)
**Benchmark**: Spotlight (Cmd+Space), plus Apple HIG for menu bar extras

---

## Executive Summary

The app functions but has significant readability issues in light mode, layout instability during state transitions, and interaction patterns that diverge from the macOS conventions users expect. The core UX benchmark is **Spotlight** — users already have muscle memory for "type to search, see results, drill into detail." Where Quarry departs from this model without reason, it creates friction.

This audit covers seven areas: color/readability, layout stability, search interaction, results presentation, detail view, database picker reliability, and identity/iconography.

---

## 1. Color & Readability in Light Mode

### Problem

Multiple UI elements become hard to read against the light system appearance:

| Element | Current Style | Issue |
|---------|--------------|-------|
| "Running" badge | `.foregroundStyle(.green)` | SwiftUI's `.green` on white background has poor contrast (WCAG AA failure) |
| Result row text preview | 11pt syntax-highlighted text | Small monospace text with `NSColor.systemRed`, `.systemPurple`, `.systemOrange` on white — washed out |
| Detail view code | 13pt syntax-highlighted text | Same color palette, slightly larger but still low contrast for orange/green tones |
| Collection capsule badge | `.secondary` text on `.quaternary` bg | Extremely faint — nearly invisible in light mode |

### Root Cause

All colors are technically "adaptive" (`NSColor.system*`, SwiftUI semantic styles), but **adaptive does not mean legible**. Apple's system colors are designed for use on opaque, contrasting surfaces. In a floating panel with the default `.window` material, the effective background is a translucent light gray that reduces contrast for saturated hues like green, orange, and red.

### Recommendations

**R1.1 — Replace status badge colors with semantic labeling or icons.**
Instead of relying on color alone to communicate state (a WCAG and HIG violation), pair color with shape:

| State | Current | Proposed |
|-------|---------|----------|
| Running | Green circle.fill + "Running" | Green circle.fill — keep, but increase font to `.footnote` and use `.foregroundStyle(.primary)` for the text, `.green` only for the icon |
| Stopped | Gray circle + "Stopped" | Same treatment — icon gets color, text stays `.primary` |

**R1.2 — Increase syntax highlighting contrast for light mode.**
Add a `colorScheme` environment check in `SyntaxHighlighter` and use darker variants for light mode:

| Token | Dark mode | Light mode (proposed) |
|-------|-----------|----------------------|
| Strings | `.systemRed` | `.systemRed` (fine) |
| Keywords | `.systemPurple` | `.systemPurple` (fine) |
| Constants | `.systemOrange` | `.systemBrown` or darker orange |
| Comments | `.secondaryLabelColor` | `.tertiaryLabelColor` is too faint — keep `.secondaryLabelColor` |
| Decorators | `.systemTeal` | `.systemCyan` or custom darker teal |

Alternatively, consider whether syntax highlighting in list rows is worth the complexity — see R3.2.

**R1.3 — Increase collection badge contrast.**
Replace `.quaternary` background with a more visible style:
```swift
// Before
.background(.quaternary, in: Capsule())
// After
.background(Color.accentColor.opacity(0.12), in: Capsule())
```

---

## 2. Layout Stability (Vertical Axis)

### Problem

The content area shifts vertically between states. When a search returns no results, the "No Results" message centers in the panel. When results exist, content fills from the top. The user perceives a "jumping" layout.

### Current State Transitions

| From | To | Vertical shift? |
|------|-----|----------------|
| Idle (top-aligned, 24pt padding) | Loading (centered via Spacer/Spacer) | **Yes — jumps to center** |
| Idle | Results (List, fills from top) | Minor |
| Idle | Empty (ContentUnavailableView, centered) | **Yes — jumps to center** |
| Loading | Results | **Yes — jumps from center to top** |
| Results | Empty | **Yes — jumps from top to center** |

### Root Cause

Three different alignment strategies are used:
1. `.idle`: `VStack { Text(...).padding(.top, 24); Spacer() }` — **top-aligned**
2. `.loading` / `.empty` / `.error`: `Spacer(); Content; Spacer()` or `ContentUnavailableView` — **center-aligned**
3. `.results`: `List` — **fills from top**

### Recommendations

**R2.1 — Adopt a fixed-origin layout.** All states should anchor content to the top of the content area, below the search field. This is what Spotlight does — the results area has a fixed top edge; content grows downward or shows an empty state near the top.

```swift
// Replace center-aligned empty states with top-aligned versions:
VStack(alignment: .center, spacing: 16) {
    Spacer().frame(height: 60)  // Fixed offset from top
    Image(systemName: "magnifyingglass")
        .font(.system(size: 28))
        .foregroundStyle(.tertiary)
    Text("No documents matched \"\(query)\".")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    Spacer()
}
```

**R2.2 — Keep the search field pinned.** The search field should never move. Currently it doesn't (it's in the top VStack), but verify this remains true as the layout evolves.

**R2.3 — Add transition animations.** Use `.animation(.easeInOut(duration: 0.15), value: viewModel.state)` on the content area to soften state transitions rather than having them snap.

---

## 3. Search Interaction — Spotlight as Benchmark

### Problem

The search field behavior diverges from Spotlight in several ways that create friction:

| Behavior | Spotlight | Quarry | Issue |
|----------|----------|--------|-------|
| Clear input | Cmd+A then Delete, or hold Backspace | Must click tiny "x" button | Spotlight has no clear button |
| Escape key | Dismisses panel | No handler | Missing expected behavior |
| Focus on open | Auto-focuses, cursor at end | Auto-focuses, cursor at end | Now matches |
| Arrow key navigation | Up/Down moves through results | Not supported (no `selection:` on List) | Missing expected behavior |
| Result activation | Enter opens selected result | Enter triggers search (via `onSubmit`) | Different model — acceptable since Quarry has explicit search |

### Root Cause

The `TextField` uses `.focused($isSearchFocused)` which positions the cursor but does not select existing text. There is no `onExitCommand` handler. The List does not use SwiftUI's `selection:` binding, so keyboard navigation is absent.

### Recommendations

**R3.1 — ~~Auto-select text on panel open.~~ CORRECTED:** Spotlight does NOT auto-select text. It places the cursor at the end of existing text so the user can continue typing. Auto-select would be destructive (the next keystroke erases the query). The correct behavior is auto-focus with cursor at end, which SwiftUI's `@FocusState` + `.onAppear` already provides.

**R3.2 — Remove the "x" clear button.** Spotlight does not have a clear button. Users clear via Cmd+A + Delete, or by holding Backspace. The clear button adds visual clutter and is an interaction pattern users don't expect in a search field.

**R3.3 — Handle Escape key.**
- First press: if detail view is showing, go back to results list
- Second press (or first if on results list): clear search and dismiss panel

```swift
.onExitCommand {
    if selectedResult != nil {
        selectedResult = nil
    } else {
        // Dismiss the panel
        NSApp.keyWindow?.close()
    }
}
```

**R3.4 — Add keyboard navigation for results.**
Use SwiftUI's `List(selection:)` binding with arrow key support:
```swift
@State private var selectedResultID: SearchResult.ID?

List(selection: $selectedResultID) { ... }
    .onChange(of: selectedResultID) { _, newID in
        selectedResult = results.first { $0.id == newID }
    }
```

This enables Up/Down arrow navigation, Enter to select, and visual highlight of the focused row — all standard macOS List behaviors.

---

## 4. Results List — Information Density

### Problem

Each result row shows four pieces of information:
1. Document name (headline)
2. Page number (caption2, right-aligned)
3. Syntax-highlighted text preview (11pt, 3 lines)
4. Collection name in capsule badge (caption2)

In a 400pt-wide panel, this creates visual clutter. The syntax-highlighted code preview at 11pt monospace wraps aggressively, making code snippets nearly unreadable — especially in light mode.

### Spotlight Comparison

Spotlight shows: **icon + title + subtitle** (2 lines max). The detail/preview appears in a separate right-hand pane, not inline. This keeps the list scannable.

### Recommendations

**R4.1 — Reduce row information to essentials.**
Show only what's needed to identify and differentiate results:

```
[icon]  Document Name                    p.3
        First line of matching text...
```

- **Remove**: Collection badge from rows (show in detail only)
- **Reduce**: Text preview to 1-2 lines, plain text (no syntax highlighting in list)
- **Add**: A format-specific icon (SF Symbol) instead of relying on the text preview to convey file type

**R4.2 — Remove syntax highlighting from list rows.**
Syntax highlighting at 11pt in a 400pt panel is unreadable. Show plain text preview with the matching query terms bolded instead. This is what Spotlight, Mail, and Finder search do — they highlight the match, not the syntax.

```swift
// Instead of SyntaxHighlighter in rows:
Text(result.text.prefix(120))
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .lineLimit(2)
```

Bolding match terms is a follow-up enhancement; plain secondary text is the minimum improvement.

**R4.3 — Consider a two-column layout for wider panels.**
If the panel width increases (see R5.2), a Spotlight-style layout with list on the left and preview on the right becomes viable. This eliminates the detail-view navigation entirely.

---

## 5. Detail View — Code Readability

### Problem

The detail view shows syntax-highlighted text at 13pt in a 400pt panel (minus 24pt padding = 376pt content width). Monospace code at 13pt fits roughly 45 characters before wrapping. Most Python code lines exceed this, causing extensive wrapping that destroys readability.

### Recommendations

**R5.1 — Reduce detail view font size for code.**
Use 11pt for code in the detail view (same as current list preview). This fits ~55 characters per line, a meaningful improvement. Non-code formats (markdown, plain text) can stay at 13pt since they benefit from readability over density.

**R5.2 — Widen the panel.**
The current 400x500 panel is narrower than Spotlight (680pt). Increasing to 500-550pt would accommodate code significantly better:

| Width | Padding | Content width | Chars at 13pt mono | Chars at 11pt mono |
|-------|---------|---------------|--------------------|--------------------|
| 400 | 24 | 376 | ~45 | ~55 |
| 500 | 24 | 476 | ~57 | ~70 |
| 550 | 24 | 526 | ~63 | ~77 |

550pt at 11pt monospace fits a standard 77-character line without wrapping.

**R5.3 — Add horizontal scroll for code blocks.**
As an alternative or complement to widening, wrap code text in a `ScrollView(.horizontal)` so long lines can be scrolled rather than wrapped. This preserves code structure.

---

## 6. Database Picker — Race Condition

### Problem

The database dropdown can show "Loading..." indefinitely, requiring a manual refresh. The user reports this as a race condition.

### Root Cause Analysis

The `.task` modifier on `DatabasePickerView` fires `loadDatabases()` on every view appearance. Several scenarios can leave it stuck:

1. **Concurrent calls**: `loadDatabases()` has no reentrancy guard. If the view reappears (e.g., state transition from `.starting` to `.running` recreates the view tree), a second call races with the first. Both set `isDiscovering = true`, but if the first call's result is discarded or errors silently, `isDiscovering` may never reset to `false`.

2. **Task cancellation**: When SwiftUI cancels a `.task` (e.g., view disappears), any `await` call inside it throws `CancellationError`. If `loadDatabases()` doesn't handle cancellation and `isDiscovering` is already `true`, it stays `true` forever.

3. **Subprocess timeout**: `CLIDatabaseDiscovery.discoverDatabases()` runs `quarry databases --json` as a subprocess. If the subprocess hangs (e.g., quarry isn't responding), there's no timeout — the Task waits indefinitely while showing "Loading...".

### Recommendations

**R6.1 — Add a reentrancy guard.**
```swift
func loadDatabases() async {
    guard !isDiscovering else { return }
    isDiscovering = true
    defer { isDiscovering = false }
    // ... discovery logic
}
```

The `defer` ensures `isDiscovering` resets even on cancellation or error.

**R6.2 — Add a subprocess timeout.**
Wrap the discovery call in a `Task` with a timeout:
```swift
try await withThrowingTaskGroup(of: [DatabaseInfo].self) { group in
    group.addTask { try await self.discovery.discoverDatabases() }
    group.addTask { try await Task.sleep(for: .seconds(5)); throw TimeoutError() }
    let result = try await group.next()!
    group.cancelAll()
    return result
}
```

**R6.3 — Show a timeout message.**
If discovery takes longer than 5 seconds, replace "Loading..." with "Discovery timed out" and show the Refresh button more prominently.

---

## 7. Identity & Iconography

### Problem

- The app icon is **not set** — all `AppIcon.appiconset` slots are empty, so macOS shows the default blank app icon.
- The menu bar icon (`doc.text.magnifyingglass`) doesn't visually connect to "Quarry" (a quarry is a stone excavation site — the mining/digging metaphor is lost).
- The menu bar icon is identical for `.stopped` and `.running` states — no visual feedback that the backend is active.

### Recommendations

**R7.1 — Design a custom app icon.**
The icon should evoke "quarry" (mining/excavation) combined with "search" (magnifying glass). Consider:
- A pickaxe + magnifying glass
- A stylized rock/gem with a search lens
- A quarry pit silhouette (layered terraces) with a document icon

This should be a proper macOS app icon following Apple's [icon design guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons): rounded rectangle, 1024x1024 master, no transparency.

**R7.2 — Differentiate menu bar icon states.**
Use SF Symbol variants or separate symbols:

| State | Icon | Rationale |
|-------|------|-----------|
| Stopped | `doc.text.magnifyingglass` (outline) | Inactive appearance |
| Starting | `doc.text.magnifyingglass` + badge or pulse animation | Activity indicator |
| Running | `doc.text.magnifyingglass` (filled variant) | Active appearance |
| Error | `exclamationmark.triangle` (current) | Keep |

**R7.3 — Consider renaming the status bar label.** Currently shows no label — only the icon. This is correct per HIG (menu bar extras should be icon-only unless they display dynamic data like a clock).

---

## 8. Accessibility & HIG Compliance

### Issues Found

| Issue | HIG Violation | Severity |
|-------|--------------|----------|
| No `accessibilityLabel` on any element | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | High |
| Color used as sole differentiator for status badge | [Color and contrast](https://developer.apple.com/design/human-interface-guidelines/color) | High |
| Clear button ("x") has no minimum 20x20pt tap target specified | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | Medium |
| No keyboard navigation for results list | [Keyboard](https://developer.apple.com/design/human-interface-guidelines/keyboards) | High |
| Syntax highlighting comment bug (keywords inside comments get keyword color) | N/A (correctness) | Low |

### Recommendations

**R8.1 — Add accessibility labels** to status badge, search field, result rows, and action buttons.

**R8.2 — Ensure color is never the sole indicator.** The status badge already includes text ("Running", "Stopped") which satisfies this, but the green/red colors should still have sufficient contrast.

**R8.3 — Fix syntax highlighting overlap.** Apply comment ranges last (highest priority) so keywords inside comments remain comment-colored.

---

## 9. Summary of Recommendations — Priority Order

| # | Recommendation | Impact | Effort |
|---|---------------|--------|--------|
| R3.1 | Auto-select text on panel open (Spotlight pattern) | High | Medium |
| R3.4 | Keyboard navigation for results (arrow keys) | High | Medium |
| R2.1 | Fixed-origin layout — no vertical centering shifts | High | Low |
| R4.2 | Remove syntax highlighting from list rows | High | Low |
| R4.1 | Reduce row info to essentials (name + preview) | High | Low |
| R1.1 | Fix status badge readability in light mode | Medium | Low |
| R6.1 | Database picker reentrancy guard | Medium | Low |
| R5.2 | Widen panel to 500-550pt | Medium | Low |
| R3.3 | Handle Escape key | Medium | Low |
| R1.2 | Improve syntax highlighting contrast (light mode) | Medium | Medium |
| R5.1 | Reduce code font size in detail view | Medium | Low |
| R7.1 | Design custom app icon | Medium | High |
| R7.2 | Differentiate menu bar icon by state | Low | Low |
| R3.2 | Remove or improve clear button | Low | Low |
| R1.3 | Increase collection badge contrast | Low | Low |
| R6.2 | Subprocess timeout for database discovery | Low | Medium |
| R8.1 | Add accessibility labels | Medium | Medium |
| R5.3 | Horizontal scroll for code in detail view | Low | Low |
| R2.3 | Add transition animations | Low | Low |
| R8.3 | Fix syntax highlighting comment priority | Low | Low |

---

## 10. Design Principles (Standing Reference)

These principles should guide all future UI work on Quarry Menu Bar:

1. **Law of Least Astonishment**: Follow Spotlight's interaction model where applicable. Users should not have to learn new patterns for search-and-browse.
2. **Fixed Geometry**: The search field and content area have fixed positions. Content changes within zones, never moves zones.
3. **Readability First**: If text isn't readable at the chosen size and color in both light and dark mode, it shouldn't be shown. Prefer omission over illegibility.
4. **Progressive Disclosure**: List rows show identification (what is this result?). Detail view shows content (what does it say?). Don't mix the two.
5. **Keyboard-First**: Menu bar apps should be operable entirely by keyboard. Focus, navigate, select, dismiss — all without a mouse.
6. **Respect the Platform**: Use system colors, system fonts, SF Symbols, and standard SwiftUI controls. Custom chrome is a last resort.
