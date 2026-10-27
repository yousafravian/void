# Intelligent Clipboard and MCP Specification

## Purpose

Defines Void's context-aware Intelligent Clipboard suggestions and its built-in local Model Context Protocol (MCP) server (`http://127.0.0.1:39725/mcp` and stdio bridge) for connecting AI tools such as Claude Desktop, Claude Code, Codex, Cursor, VS Code, Windsurf, and Custom MCP clients.

## ADDED Requirements

### Requirement: Intelligent Clipboard Context-Aware Suggestions
When `"Intelligent Clipboard"` is enabled in `Settings -> Intelligence`, Void SHALL analyze the active application's context (frontmost app, window title, and focused accessibility text/screen context) on-device to surface a `Suggestions` view containing the clipboard items most relevant to what the user is currently typing or working on.

#### Scenario: Surface relevant items in Suggestions
- **WHEN** the user is drafting a message or document (e.g., typing `"Here's the cabin:"` in Mail or Messages) and opens Void
- **THEN** Void's `Suggestions` pill highlights recently copied items matching that context (such as a cabin Airbnb link, packing list text, and photo) for instant one-keystroke pasting

### Requirement: Built-In Local MCP Server with Per-Client Approval
When `"Enable MCP"` is turned on in `Settings -> MCP & AI Tools`, Void SHALL run a local Model Context Protocol server bound exclusively to `127.0.0.1` (default `http://127.0.0.1:39725/mcp` supporting Streamable HTTP/SSE plus a local CLI stdio proxy) that requires user approval or a private bearer token before any AI client can access clipboard data.

#### Scenario: Start local MCP server and require approval
- **WHEN** the user enables `Enable MCP` in `Settings -> MCP & AI Tools` and an AI tool initiates a connection
- **THEN** Void binds the local MCP endpoint on `127.0.0.1:39725/mcp`, prompts the user to approve the connecting client (or validates the configured bearer token), and records the tool in the `Connected AI Tools` list with its `"Last connected"` timestamp

### Requirement: Comprehensive MCP Tools for Clipboard and Pinboard Operations
The Void MCP server SHALL expose structured MCP tools allowing approved AI clients to search clipboard history and pinboards, read recent or specific items (including text, links, file paths, and OCR text/images), save new items to Void, and create or organize Pinboards.

#### Scenario: Search and retrieve clipboard context via MCP
- **WHEN** a connected AI client invokes `search_clipboard` or `get_recent_items` with optional query, content type, source app, pinboard, or date range parameters
- **THEN** Void returns matching clipboard items with their IDs, types, titles, text/URL payloads, OCR text, source apps, timestamps, and pinboard assignments

#### Scenario: Save items and manage Pinboards via MCP
- **WHEN** a connected AI client invokes `create_clipboard_item`, `list_pinboards`, `create_pinboard`, or `pin_item`
- **THEN** Void creates the requested item or pinboard, assigns the specified items to the target pinboard, and updates the live UI immediately

### Requirement: Guided AI Tool Connection Wizard and Access Management
`Settings -> MCP & AI Tools` SHALL provide a `Connect AI Tool…` wizard with tailored one-click configuration or copyable Terminal commands for **Claude Desktop**, **Claude Code**, **Codex**, **Cursor**, **VS Code**, **Windsurf**, and **Custom AI Tool** (server URL + secret token), plus a `Connected AI Tools` list where each tool can be disconnected at any time.

#### Scenario: Connect Claude Code, Codex, Cursor, or Custom MCP client
- **WHEN** the user clicks `Connect AI Tool…` and selects `Claude Code`, `Codex`, `Cursor`, `Claude Desktop`, `VS Code`, `Windsurf`, or `Custom AI Tool`
- **THEN** Void presents the exact setup flow (copyable Terminal registration command, automatic config installation, or Server URL + Bearer Token with `Advanced…` port/token regeneration) and allows revoking access via the `⋯ -> Disconnect` menu next to any connected tool
