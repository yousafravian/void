# Power Search and Filters Specification

## Purpose

Defines Void's Power Search engine, including instant type-to-search, full-text and inside-image OCR search with match highlighting, inline smart filter chips, Pinboard filters, and Jump to History (`Command-G`).

## Requirements

### Requirement: Instant Type-to-Search and Filter Bar Activation
When the Void panel is open, typing printable characters or pressing `Command-F` SHALL immediately focus the Power Search field; pressing `Command-F` a second time while search is focused SHALL expand the full filter bar (`Content Type`, `Source App`, `Date`, `Pinboard`).

#### Scenario: Start searching immediately upon opening Void
- **WHEN** the user opens Void with `Shift-Command-V` and immediately types a query (e.g., `"meeting notes"`)
- **THEN** the search field activates automatically, captures the keystrokes, and filters visible cards in real time

#### Scenario: Expand full filter bar with second Command-F
- **WHEN** the search field is already active and the user presses `Command-F` again (or clicks the filter icon)
- **THEN** the expanded filter bar reveals selectable chips for Content Types, Source Applications, Date Ranges, and Pinboards, and `Tab` switches focus between the search input and the results scroller

### Requirement: Full-Text and Inside-Image OCR Search
Power Search SHALL query item text, custom titles/labels, URLs, filenames, source application names, and OCR text recognized inside images with sub-50ms latency using SQLite FTS5, highlighting matched text inside both text and image cards.

#### Scenario: Match text inside copied images
- **WHEN** the user searches for a word or phrase that appears inside a copied screenshot or image
- **THEN** the matching `Image` card is returned in the search results and the recognized text region matching the query is visually highlighted on the card and in Quick Look preview

### Requirement: Inline Smart Filter Chips and Suggestions
As the user types in the search bar, Void SHALL suggest matching inline filter tokens for Content Type (`Text`, `Link`, `Image`, `File`, `Color`, `Code`), Source App (e.g., `Safari`, `Linear`, `Mail`), Relative Date (`Today`, `Yesterday`, `Last 7 Days`, `Last Week`, `Last Month`), and Pinboards (one or multiple Pinboards).

#### Scenario: Apply inline smart filter chips
- **WHEN** the user types `"Safari"` or `"Link"` or selects suggested filter pills in the search field
- **THEN** Void converts the selection into structured filter chips (e.g., `[App: Safari] [Type: Link] [Date: Last Week]`) and intersects them with any free-text query

#### Scenario: Filter across one or multiple Pinboards
- **WHEN** the user selects one or more Pinboard filters in Power Search
- **THEN** search results are restricted to items belonging to the selected Pinboards (or all of Clipboard History and Pinboards when cleared)

### Requirement: Jump to History and Show in Context
From any item returned in Power Search results, the user SHALL be able to press `Command-G` or select `Show in Clipboard` / `Show in <Pinboard>` from the context menu to exit search and scroll directly to that item's original chronological position in Clipboard History or its Pinboard.

#### Scenario: Jump from search result to surrounding chronological context
- **WHEN** the user selects a card in Power Search results and presses `Command-G` (or right-clicks and selects `Show in Clipboard`)
- **THEN** Void clears the active search state, switches to Clipboard History (or the chosen Pinboard), scrolls horizontally to center the target card, and highlights it alongside the items copied immediately before and after it
