# UI Shell and Panel Specification

## Purpose

Defines Void's native macOS Liquid Glass bottom-sliding horizontal panel, resizable and compact display modes, menu bar status item, rich color-coded clipboard card anatomy, and full keyboard navigation.

## Requirements

### Requirement: Bottom-Anchored Liquid Glass Panel
The application SHALL present a borderless, non-activating floating panel (`NSPanel`) anchored across the bottom edge of the active screen with macOS Liquid Glass translucency, spring slide-in/out animations, and automatic Dark and Light mode adaptation.

#### Scenario: Summon panel on active display
- **WHEN** the user presses the global shortcut (`Shift-Command-V`) or left-clicks the Void menu bar icon
- **THEN** the panel slides up from the bottom of the screen currently containing the mouse cursor or active application without stealing focus from the frontmost app

#### Scenario: Dismiss panel
- **WHEN** the user presses `Escape`, presses `Shift-Command-V` again while on the final tab or when configured to toggle, or clicks outside the panel
- **THEN** the panel animates down off-screen and restores interaction to the previously active application

### Requirement: Resizable Window and Compact Mode
The panel SHALL allow users to drag its top edge to resize the window vertically between a full-height preview layout and a Compact Mode card strip, persisting the chosen height across launches.

#### Scenario: Resize panel height
- **WHEN** the user drags the top border of the bottom panel upward or downward
- **THEN** the panel resizes smoothly within minimum (Compact Mode) and maximum height bounds and updates card preview proportions dynamically

#### Scenario: Toggle Compact Mode
- **WHEN** the user resizes the panel to its minimum height threshold or toggles Compact Mode
- **THEN** cards render in a condensed layout emphasizing the header, title, and concise snippet preview

### Requirement: Menu Bar Status Item and Quick Menu
The application SHALL provide a persistent macOS menu bar icon (`NSStatusItem`) where a primary click toggles the main panel and a secondary (`Control-Click` or right-click) opens a status menu with pause controls, Settings, Help, and Quit actions.

#### Scenario: Left-click menu bar icon
- **WHEN** the user left-clicks the Void menu bar icon
- **THEN** the bottom sliding panel toggles visibility on the active screen

#### Scenario: Right-click menu bar icon and pause menu
- **WHEN** the user right-clicks the Void menu bar icon
- **THEN** a native menu appears displaying `Pause Void` (`Command-T`, with submenu options `Pause for 15m`, `Pause for 30m`, `Pause for 1h`, and `Resume` when paused), `Settings…` (`Command-,`), `About Void`, `Help`, and `Quit Void` (`Command-Q`)

### Requirement: Clipboard Card Anatomy and Dynamic Header Coloring
Each clipboard item in the horizontal scroller SHALL render as a rounded Liquid Glass card containing a color-coded header bar derived from the source application's dominant icon color, the source app icon on the right, item type/custom title and relative timestamp on the left, a rich content body preview, and a metadata footer.

#### Scenario: Render card header and metadata footer
- **WHEN** a clipboard item captured from an application (such as Safari, Xcode, or Notes) is displayed in the horizontal list
- **THEN** the card header is tinted with the dominant color of that source application's icon, displays the item title or type and relative timestamp (e.g., `just now`, `3m`, `2h`), and shows type-specific metadata in the footer (`N characters`, image pixel dimensions `W × H`, HEX color code, or file size)

#### Scenario: Render Quick Paste index badge
- **WHEN** cards 1 through 9 are visible in the current horizontal viewport
- **THEN** each card displays its corresponding Quick Paste shortcut badge (`⌘1` through `⌘9`) when the Quick Paste modifier key is held or in the card footer

### Requirement: Horizontal Scrolling and Keyboard Navigation
The panel SHALL support smooth horizontal trackpad/mouse scrolling and complete keyboard navigation for selecting, extending selection, and cycling across cards and pinboards.

#### Scenario: Navigate single items with arrow keys
- **WHEN** the panel is open and the user presses `Right Arrow`, `Left Arrow`, `Command-Up Arrow`, or `Command-Down Arrow`
- **THEN** selection moves to the next item, previous item, first item (`Command-Up Arrow`), or last item (`Command-Down Arrow`) and scrolls the selected card into view

#### Scenario: Multi-select items via keyboard and mouse
- **WHEN** the user presses `Shift-Right Arrow`, `Shift-Left Arrow`, `Command-A`, `Command-Click`, or `Shift-Click` on cards
- **THEN** multiple cards are highlighted in an active selection set for bulk pasting, copying, pinning, or deletion

### Requirement: Screen Sharing Invisibility Control
The panel, preview overlays, and Paste Stack window SHALL respect the user's `"Show during screen sharing"` privacy setting by configuring `NSWindow.SharingType`.

#### Scenario: Hide Void during screen sharing
- **WHEN** `"Show during screen sharing"` is disabled in `Settings -> Privacy` and the user shares their screen or records a screenshot
- **THEN** all Void windows use `NSWindow.SharingType.none` so they remain invisible to remote viewers and screen capture streams
