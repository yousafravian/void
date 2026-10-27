# Settings, Storage, and Shortcuts Specification

## Purpose

Defines Void's local SQLite + FTS5 persistence engine, history retention policies, multi-tab Settings window (`General`, `Privacy`, `Shortcuts`, `MCP & AI Tools`), customizable global shortcuts and modifiers, Undo support (`Command-Z`), and macOS App Intents / Shortcuts integration.

## ADDED Requirements

### Requirement: Local-First SQLite + FTS5 Database and Asset Store
Void SHALL store all clipboard metadata, Pinboards, and full-text/OCR search indices locally in `~/Library/Application Support/Void/Void.sqlite` (using WAL mode and SQLite FTS5) and store large binary payloads (images, thumbnails, RTF blobs) in content-addressed local files under `~/Library/Application Support/Void/Assets/`.

#### Scenario: Persist and reload large clipboard history locally
- **WHEN** the user copies thousands of text snippets, links, images, and files across app restarts
- **THEN** Void persists all items and FTS5 indices on disk, deduplicates binary assets by SHA-256 hash, and loads the visible card window in under 30ms on startup

### Requirement: History Retention Policy Engine and Erase History
`Settings -> General` SHALL provide a `Keep History` retention selector with options for `Day`, `Week`, `Month` (default), `Year`, and `Forever`, alongside an `Erase History…` button that clears unpinned clipboard history while preserving all Pinboards.

#### Scenario: Automatically purge expired unpinned items
- **WHEN** the retention period is set to `Day`, `Week`, `Month`, or `Year` and background maintenance runs
- **THEN** Void deletes unpinned clipboard items older than the configured cutoff (along with any unreferenced asset files) while keeping all pinned items untouched

### Requirement: Multi-Tab Settings Window
Pressing `Command-,` (or choosing `Settings…` from the menu bar) SHALL open the native Settings window organized into `General`, `Privacy`, `Shortcuts`, and `MCP & AI Tools` (Intelligence) panes.

#### Scenario: Configure General settings
- **WHEN** the user opens `Settings -> General`
- **THEN** they can toggle `Open at login` (`SMAppService`), `Run in background`, `Sound effects`, `Always paste as Plain Text`, choose `Paste Items` (`To active app` vs `To Clipboard`), and configure `Keep History` retention (`Day`, `Week`, `Month`, `Year`, `Forever`) or `Erase History…`

#### Scenario: Configure Privacy settings
- **WHEN** the user opens `Settings -> Privacy`
- **THEN** they can toggle `Show during screen sharing`, `Generate link previews`, `Ignore confidential content`, and `Ignore transient content`, and add (`+`) or remove (`-`) apps in the `Ignore Applications` list (with `Passwords.app` included by default)

### Requirement: Customizable Global Shortcuts and Modifiers
`Settings -> Shortcuts` SHALL allow customizing the four primary global/navigation shortcuts (`Activate Void` default `Shift-Command-V`, `Activate Paste Stack` default `Shift-Command-C`, `Show next Pinboard` default `Command-Right Arrow`, `Show previous Pinboard` default `Command-Left Arrow`), swapping the single modifier key (`Command`, `Shift`, `Control`, or `Option`) used for `Quick Paste` and `Plain Text mode`, and resetting all shortcuts to defaults.

#### Scenario: Reassign global shortcut or modifier key
- **WHEN** the user records a new shortcut for `Activate Void` or changes the `Plain Text mode` modifier in `Settings -> Shortcuts`
- **THEN** Void immediately registers the new global hotkeys and updates shortcut badges across the UI, and restores factory defaults when `Reset to Defaults` is clicked

### Requirement: Undo Support for Destructive Actions
Pressing `Command-Z` while the Void panel is active SHALL undo recent item deletions, renames, in-place edits, or pinboard removals.

#### Scenario: Undo item deletion with Command-Z
- **WHEN** the user deletes one or more cards with `Delete` (`⌫`) and presses `Command-Z`
- **THEN** Void restores the deleted card(s) to their original position in Clipboard History and/or Pinboard

### Requirement: macOS App Intents and Apple Shortcuts Actions
Void SHALL expose native `AppIntents` actions to the macOS **Shortcuts** app and Siri so users can automate clipboard and pinboard workflows.

#### Scenario: Run Void actions inside macOS Shortcuts
- **WHEN** the user builds a workflow in the macOS Shortcuts app using Void's actions (`Get Latest Clipboard Item`, `Search Clipboard Items`, `Get Items from Pinboard`, `Add Item to Pinboard`, `Paste Item`)
- **THEN** Void executes the intent against its local database and returns or writes the requested clipboard content
