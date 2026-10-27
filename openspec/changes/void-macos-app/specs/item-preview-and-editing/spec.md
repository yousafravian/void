# Item Preview and Editing Specification

## Purpose

Defines Void's Quick Look (`Space`) rich preview overlay, interactive web and media previews, in-place text and link editing (`Command-E`), custom item renaming (`Command-R`), image rotation and OCR text extraction, built-in color picker, and Apple Intelligence Writing Tools integration.

## ADDED Requirements

### Requirement: Quick Look Rich Preview Overlay
Pressing `Space` on a selected card (or choosing `Quick Look` from the context menu) SHALL open a rich preview window tailored to the item's content type, displaying detailed metadata in the footer (`characters • words • lines` for text, `W × H • MB` for images, and `filename • MB` with `Reveal in Finder` for files).

#### Scenario: Preview text, code, links, media, and PDFs
- **WHEN** the user selects a card in Void and presses `Space`
- **THEN** Void opens a rich preview overlay rendering scrollable full text or syntax-highlighted code, an interactive `WKWebView` webpage preview for links, an audio/video player for media files, or a multi-page PDF viewer, and closes or switches items as the user navigates with arrow keys or presses `Space` again

### Requirement: Image Rotation, OCR Text Selection, and Color Picker in Preview
In the Quick Look preview (and card context menu), `Image` items SHALL support 90-degree rotation and one-click `Extract Text` / Live Text selection, while `Color` items SHALL provide an interactive Color Picker to inspect and adjust the color value.

#### Scenario: Rotate image or extract OCR text from preview
- **WHEN** the user previews an `Image` item and clicks `Rotate` or `Extract Text`
- **THEN** Void rotates the stored image in place or copies/allows selection of the recognized OCR text from the image

#### Scenario: Adjust color in Color preview
- **WHEN** the user opens Quick Look or edits a `Color` card
- **THEN** an interactive macOS color picker allows adjusting the color swatch and updates the card's HEX/RGB value on save

### Requirement: In-Place Text and URL Editing
Pressing `Command-E` (or clicking `Edit` in the card context menu or preview header) on a `Text` or `Link` item SHALL open an in-place editor on the card with rich-text formatting controls (`B`, `I`, `U`, `S`) and `Cancel` / `Save` buttons.

#### Scenario: Edit copied text or link in place
- **WHEN** the user selects a `Text` or `Link` card, presses `Command-E`, modifies the text or styling (`Bold`, `Italic`, `Underline`, `Strikethrough`), and clicks `Save`
- **THEN** Void updates the item's stored content, recalculates character/word/line counts or link metadata, and updates the full-text search index

### Requirement: Apple Intelligence Writing Tools Integration
While editing text in place or via the card context menu's `Writing Tools` submenu on supported macOS versions, Void SHALL expose native macOS Apple Intelligence Writing Tools (`Proofread`, `Rewrite`, `Friendly`, `Professional`, `Concise`, `Summarize`, `Compose`).

#### Scenario: Refine clipboard text with Writing Tools
- **WHEN** the user right-clicks a `Text` card and selects `Writing Tools -> Proofread` (or invokes Writing Tools inside the `Command-E` editor)
- **THEN** macOS Writing Tools processes the text and applies the accepted revision directly to the clipboard item

### Requirement: Custom Item Title and Rename
Pressing `Command-R` (or clicking the item title in the card header or selecting `Rename` from the context menu) SHALL allow the user to assign or clear a custom title/label on any clipboard card.

#### Scenario: Rename card for quick identification and search
- **WHEN** the user presses `Command-R` on a card, types `"Launch Metrics SQL"`, and presses `Return`
- **THEN** the card header displays `"Launch Metrics SQL"` instead of the generic type label and indexes the custom title for Power Search
