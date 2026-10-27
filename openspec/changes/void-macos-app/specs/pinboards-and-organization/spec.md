# Pinboards and Organization Specification

## Purpose

Defines Void's color-coded Pinboards, top navigation bar management, single-pinboard-per-item semantics, drag-and-drop pinning and card reordering, retention immunity, and local pinboard export/import.

## ADDED Requirements

### Requirement: Pinboard Creation, Color-Coding, Reordering, and Deletion
Users SHALL be able to create (`Shift-Command-N` or clicking `+` in the top bar), rename, assign a custom indicator color to, reorder via drag-and-drop, and delete Pinboards displayed alongside Clipboard History in the panel's top navigation bar.

#### Scenario: Create and color-code a new Pinboard
- **WHEN** the user clicks the `+` button in the top navigation bar or presses `Shift-Command-N`
- **THEN** Void creates a new Pinboard tab, prompts for a name and color swatch, and makes it available in the navigation bar and context menus

#### Scenario: Switch between Pinboards via keyboard
- **WHEN** the user presses `Command-Right Arrow` (Next Pinboard) or `Command-Left Arrow` (Previous Pinboard)
- **THEN** the active tab switches to the adjacent Pinboard (or Clipboard History) and displays its cards immediately

### Requirement: Single-Pinboard Membership and History Preservation
Pinning an item SHALL retain the item in Clipboard History while associating it with the target Pinboard; each item SHALL belong to at most one Pinboard at a time, moving from its previous Pinboard if pinned to a new one.

#### Scenario: Pin item from Clipboard History
- **WHEN** the user drags a card from Clipboard History onto a Pinboard tab or chooses `Pin -> <Pinboard Name>` from the card's context menu
- **THEN** the item appears in the selected Pinboard, displays the Pinboard's color dot and name badge on its card in Clipboard History, and remains in Clipboard History

#### Scenario: Move item between Pinboards
- **WHEN** an item already assigned to Pinboard A is dragged onto or pinned to Pinboard B
- **THEN** the item is removed from Pinboard A and added to Pinboard B while remaining in Clipboard History

### Requirement: Custom Card Ordering Inside Pinboards
While Clipboard History is strictly ordered chronologically by last copy time, each Pinboard SHALL support user-defined card ordering via drag-and-drop.

#### Scenario: Reorder cards within a Pinboard
- **WHEN** the user is viewing a Pinboard and drags a card horizontally to a new position
- **THEN** Void updates and persists the custom sort order of cards within that Pinboard

### Requirement: Retention Immunity for Pinned Items
Items assigned to any Pinboard SHALL be exempt from automatic history expiration and `Erase History` cleanup, remaining stored until explicitly unpinned or deleted by the user.

#### Scenario: Preserve pinned items during history retention cleanup
- **WHEN** the automatic history retention policy purges expired items or the user triggers `Erase History` in Settings
- **THEN** all items belonging to a Pinboard remain intact in their Pinboard

### Requirement: Local Pinboard Export and Import
To support local backup and sharing without requiring a paid cloud subscription, Void SHALL allow exporting any Pinboard (including all item payloads and metadata) to a portable `.voidboard` archive file and importing `.voidboard` files or sharing individual items via the native macOS `Share` menu.

#### Scenario: Export and import a Pinboard archive
- **WHEN** the user right-clicks a Pinboard tab and selects `Export Pinboard…` or imports a `.voidboard` file
- **THEN** Void serializes or restores the Pinboard's name, color, ordered items, and media blobs locally
