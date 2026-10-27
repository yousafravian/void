# Clipboard Capture Engine Specification

## Purpose

Defines Void's background `NSPasteboard` monitoring engine, supported data representations, rich link metadata fetching, on-device Vision OCR indexing, Continuity Camera integration, manual item creation, and privacy/exclusion filters.

## ADDED Requirements

### Requirement: Continuous Background Pasteboard Monitoring
The application SHALL monitor `NSPasteboard.general.changeCount` in the background at a low-overhead interval (e.g., 150ms–250ms) and capture every new copy operation along with the frontmost source application's bundle identifier, name, icon, and timestamp.

#### Scenario: Capture new copy from active application
- **WHEN** the user copies content in any non-excluded macOS application while capture is active
- **THEN** Void detects the `changeCount` increment, extracts all supported pasteboard representations, records the frontmost application (`NSWorkspace.shared.frontmostApplication`), and inserts the new item at the front of Clipboard History

#### Scenario: Deduplicate consecutive identical copies
- **WHEN** the user copies content identical to the most recent item in Clipboard History
- **THEN** Void updates the existing item's timestamp and moves it to the first position in Clipboard History instead of creating a duplicate card

### Requirement: Multi-Format Content Classification and Storage
The capture engine SHALL classify and store copied items across six primary types: Text (Plain Text, RTF, HTML, and Source Code), Link (URLs), Image (PNG/TIFF/JPEG/HEIC), File (single or multiple Finder file/folder URLs), and Color (6-character HEX or RGB color strings).

#### Scenario: Capture rich text and code snippets
- **WHEN** text containing RTF/HTML styling or source code is copied
- **THEN** Void preserves both the formatted representation (`public.rtf` / `public.html`) and plain-text representation (`public.utf8-plain-text`), rendering styled text or syntax-highlighted code on the card and recording character, word, and line counts

#### Scenario: Recognize copied color codes
- **WHEN** a standalone 6-character hexadecimal color string (with or without leading `#`) or CSS `rgb()`/`hsl()` color value is copied
- **THEN** Void classifies the item as a `Color` card, fills the card preview swatch with the parsed color, and displays the normalized HEX code

#### Scenario: Capture files and folders from Finder
- **WHEN** one or more files or folders are copied in Finder (`public.file-url`)
- **THEN** Void captures the file URLs, icons, filenames, and byte sizes, and supports opening the files in a user-selected application or revealing them in Finder

### Requirement: Rich Link Previews and Metadata Fetching
When a URL is copied and `"Generate link previews"` is enabled in `Settings -> Privacy`, the capture engine SHALL asynchronously fetch the webpage's title, OpenGraph/LinkPresentation metadata, favicon, and preview image.

#### Scenario: Fetch link preview metadata
- **WHEN** a valid `http` or `https` URL is copied and `"Generate link previews"` is enabled
- **THEN** Void creates a `Link` card immediately with the URL and asynchronously updates the card with the fetched page title, domain, and thumbnail preview

#### Scenario: Skip network fetch when link previews are disabled
- **WHEN** `"Generate link previews"` is disabled in `Settings -> Privacy` and a URL is copied
- **THEN** Void saves the `Link` card using only the local URL string without making any outbound network request

### Requirement: On-Device Vision OCR for Copied Images
Whenever an image or screenshot is captured, the engine SHALL asynchronously run macOS `Vision` framework text recognition (`VNRecognizeTextRequest` with `.accurate` recognition level) on-device and index all recognized text and bounding boxes for search and extraction.

#### Scenario: Index text inside copied screenshot
- **WHEN** the user copies an image or takes a screenshot to the clipboard (`Control-Shift-Command-3` or `4`)
- **THEN** Void stores the image dimensions (`W × H`) and byte size, runs `VNRecognizeTextRequest` in the background, and saves the recognized text strings and normalized bounding boxes to the local search index

### Requirement: Manual Item Creation and Continuity Camera Import
The application SHALL allow users to manually create new text or link items directly inside Void (`Command-N`) and import photos or scanned documents from a nearby iPhone or iPad via macOS Continuity Camera.

#### Scenario: Create new text item with Command-N
- **WHEN** the panel is active and the user presses `Command-N` or selects `New Text Item` from the menu
- **THEN** Void inserts a new editable card in the current view (Clipboard History or active Pinboard) and opens the in-place text editor immediately

#### Scenario: Import from iPhone via Continuity Camera
- **WHEN** the user invokes `Import from iPhone / iPad` (`Take Photo` or `Scan Documents`) from Void's menu
- **THEN** Void receives the captured image or PDF scan via AppKit Continuity Camera responder APIs and adds it as a new item in Clipboard History

### Requirement: Confidential, Transient, and Excluded Application Filtering
The capture engine SHALL ignore pasteboard payloads marked as confidential or transient and skip copies originating from any application in the user's `Ignore Applications` list (which MUST include `com.apple.Passwords` by default).

#### Scenario: Ignore password manager confidential copies
- **WHEN** `"Ignore confidential content"` or `"Ignore transient content"` is enabled and the pasteboard contains `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, or `org.nspasteboard.AutoGeneratedType` (or known password manager markers)
- **THEN** Void ignores the pasteboard change and does not store the sensitive payload

#### Scenario: Ignore excluded source application
- **WHEN** the frontmost application at the moment of copy matches a bundle identifier in `Settings -> Privacy -> Ignore Applications`
- **THEN** Void skips capturing the clipboard change

### Requirement: Timed and Manual Pause Capture
Users SHALL be able to pause and resume clipboard capture via `Command-T` or the menu bar status menu, either indefinitely until resumed or for a preset duration (`15m`, `30m`, `1h`).

#### Scenario: Pause capture for preset duration
- **WHEN** the user presses `Command-T` or chooses `Pause for 15m`, `Pause for 30m`, or `Pause for 1h` from the menu bar
- **THEN** Void stops monitoring `NSPasteboard`, updates the menu bar icon to indicate the `Paused` state, and automatically resumes capture when the timer expires or when the user clicks `Resume`
