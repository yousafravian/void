# Pasting and Paste Stack Specification

## Purpose

Defines Void's Direct Paste mechanics via macOS Accessibility, clipboard fallback, Plain Text pasting, Quick Paste numbered shortcuts (`Command-1`–`9`), drag-and-drop image/file export, and the floating Paste Stack sequential queue (`Shift-Command-C`).

## ADDED Requirements

### Requirement: Direct Paste to Active Application and Clipboard Fallback
When `"Paste Items: To active app"` is selected in Settings and macOS Accessibility permission (`AXIsProcessTrusted`) is granted, pressing `Return` or double-clicking a card SHALL write the item to `NSPasteboard`, dismiss Void, and synthesize `Command-V` into the target application; if `"To Clipboard"` is selected or Accessibility is not granted, Void SHALL copy the item to `NSPasteboard` without synthesizing `Command-V`.

#### Scenario: Direct paste to active app on Return or double-click
- **WHEN** the user single-clicks to select a card and presses `Return` (or double-clicks a card) with Direct Paste enabled
- **THEN** Void places the item's payload on `NSPasteboard.general`, hides the panel, restores focus to the target application, and dispatches a `CGEvent` `Command-V` keystroke

#### Scenario: Copy to clipboard explicitly with Command-C
- **WHEN** the user selects one or more cards in Void and presses `Command-C` (or selects `Copy` from the context menu)
- **THEN** Void writes the selected item(s) to `NSPasteboard.general` and dismisses the panel without triggering an automatic paste into the active app

### Requirement: Paste as Plain Text Mode
Users SHALL be able to strip formatting when pasting by pressing `Shift-Return` (or their configured Plain Text modifier + `Return`), pressing `Shift-Command-1` through `9`, choosing `Paste as Plain Text` in the context menu, or enabling `"Always paste as Plain Text"` in `Settings -> General`.

#### Scenario: One-off Paste as Plain Text via Shift-Return
- **WHEN** the user selects a rich text, HTML, or link card in Void and presses `Shift-Return`
- **THEN** Void writes only `public.utf8-plain-text` to `NSPasteboard.general` and pastes the unformatted text into the active application

### Requirement: Quick Paste with Numbered Shortcuts
When the Void panel is active, pressing `Command-1` through `Command-9` (using the configurable Quick Paste modifier) SHALL immediately paste the 1st through 9th visible item in the current list, and `Shift-Command-1` through `9` SHALL paste that item as plain text.

#### Scenario: Quick Paste nth item
- **WHEN** Void is open and the user presses `Command-3`
- **THEN** Void immediately pastes the 3rd card in the currently visible list into the active application

### Requirement: Drag-and-Drop and Paste Images as Files
Users SHALL be able to drag any card out of Void into another application or Finder, and `Image` cards SHALL provide both image data and a temporary file URL promise (`NSFilePromiseProvider` / `.png` file URL) so copied screenshots/images can be dropped or pasted directly as files into Finder or browser upload fields.

#### Scenario: Drag or paste copied image as a file into Finder or browser
- **WHEN** the user drags an `Image` card into a Finder folder or pastes it into a file-upload target
- **THEN** Void materializes a `.png` file on disk and delivers the file URL so the destination receives a valid image file

### Requirement: Open Links and Reveal Files in Finder
Pressing `Command-O` (or selecting `Open` in the context menu) on a `Link` or `File` card SHALL open the URL in the default browser or open the file in its default or user-chosen application; `File` cards SHALL also offer `Reveal in Finder`.

#### Scenario: Open link or reveal file
- **WHEN** the user selects a `Link` card and presses `Command-O` or selects `Reveal in Finder` on a `File` card
- **THEN** Void opens the URL via `NSWorkspace.shared.open` or highlights the file in a Finder window via `activateFileViewerSelecting`

### Requirement: Paste Stack Sequential Queue
Pressing `Shift-Command-C` SHALL open the floating, always-on-top **Paste Stack** window, which captures every subsequent `Command-C` copy into an ordered queue and pops the next item automatically on each `Command-V` paste until the stack is empty.

#### Scenario: Collect and sequentially paste items with Paste Stack
- **WHEN** the user activates Paste Stack with `Shift-Command-C`, copies three items across apps with `Command-C`, and then presses `Command-V` three times in a destination document
- **THEN** Paste Stack queues all three items visually, pastes them one by one in the selected order (FIFO top-to-bottom by default, or LIFO bottom-to-top when the direction arrows button is toggled), and removes each item from the stack after it is pasted

#### Scenario: Manage items inside Paste Stack
- **WHEN** Paste Stack is open and the user toggles the Plain Text (`T`) button, toggles Pause, or swipes left with two fingers (or chooses `Delete`) on a queued item
- **THEN** Paste Stack switches to plain-text output, pauses/resumes stack collection, or removes the unwanted item from the queue without affecting main Clipboard History
