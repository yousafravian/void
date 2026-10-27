import Foundation
import Network
import AppKit

public final class MCPServerService: ObservableObject, @unchecked Sendable {
    public static let shared = MCPServerService()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var activePort: UInt16 = 39725
    @Published public private(set) var connectedClients: [MCPClientRecord] = []

    private let database: DatabaseManager
    private let assetStore: AssetStore
    private let settings: VoidSettings
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.voidapp.mac.mcp-server", qos: .userInitiated)
    public var onDataMutated: (() -> Void)?

    public init(
        database: DatabaseManager = .shared,
        assetStore: AssetStore = .shared,
        settings: VoidSettings = .shared
    ) {
        self.database = database
        self.assetStore = assetStore
        self.settings = settings
        self.activePort = settings.mcpPort
        self.connectedClients = database.fetchMCPClients()
    }

    public var endpointURLString: String {
        "http://127.0.0.1:\(settings.mcpPort)/mcp"
    }

    public func refreshClients() {
        let records = database.fetchMCPClients()
        DispatchQueue.main.async {
            self.connectedClients = records
        }
    }

    public func startIfNeeded() {
        guard settings.mcpEnabled else {
            stop()
            return
        }
        start(port: settings.mcpPort)
    }

    public func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

        do {
            let newListener = try NWListener(using: params)
            newListener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.activePort = port
                    case .failed, .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            newListener.start(queue: queue)
            self.listener = newListener
        } catch {
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    public func registerOrConnectClient(type: MCPClientType, customName: String? = nil) -> MCPClientRecord {
        let name = customName ?? type.rawValue
        let existing = database.fetchMCPClients().first { $0.clientType == type && $0.clientName == name }
        let record = MCPClientRecord(
            id: existing?.id ?? UUID().uuidString,
            clientType: type,
            clientName: name,
            tokenHash: AssetStore.sha256Hex(of: settings.mcpAuthToken),
            isApproved: true,
            lastConnectedAt: Date(),
            createdAt: existing?.createdAt ?? Date()
        )
        database.saveMCPClient(record)
        refreshClients()
        return record
    }

    public func disconnectClient(id: String) {
        database.deleteMCPClient(id: id)
        refreshClients()
    }

    public func configurationSnippet(for clientType: MCPClientType) -> String {
        let url = endpointURLString
        let token = settings.mcpAuthToken
        let voidMCPPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/void-mcp")
            .path

        switch clientType {
        case .claudeCode:
            return "claude mcp add --transport http void \(url) --header \"Authorization: Bearer \(token)\""
        case .codex:
            return """
            [mcp_servers.void]
            url = "\(url)"
            bearer_token = "\(token)"
            """
        case .claudeDesktop, .cursor, .vscode, .windsurf, .custom:
            return """
            {
              "mcpServers": {
                "void": {
                  "command": "\(voidMCPPath)",
                  "env": {
                    "VOID_MCP_TOKEN": "\(token)"
                  },
                  "url": "\(url)",
                  "headers": {
                    "Authorization": "Bearer \(token)"
                  }
                }
              }
            }
            """
        }
    }

    // MARK: - HTTP Connection Handler
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let rawRequest = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let parts = rawRequest.components(separatedBy: "\r\n\r\n")
            let headerBlock = parts.first ?? ""
            let bodyBlock = parts.dropFirst().joined(separator: "\r\n\r\n")

            var headers: [String: String] = [:]
            for line in headerBlock.components(separatedBy: "\r\n").dropFirst() {
                if let colon = line.firstIndex(of: ":") {
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    headers[key] = val
                }
            }

            let clientAgent = headers["x-mcp-client"] ?? headers["user-agent"] ?? "MCP Client"
            let responseData = self.handleJSONRPCRequest(
                bodyData: Data(bodyBlock.utf8),
                authHeader: headers["authorization"],
                clientHint: clientAgent
            )

            let httpHeader = """
            HTTP/1.1 200 OK\r
            Content-Type: application/json\r
            Access-Control-Allow-Origin: *\r
            Content-Length: \(responseData.count)\r
            Connection: close\r
            \r\n
            """
            var fullPayload = Data(httpHeader.utf8)
            fullPayload.append(responseData)
            connection.send(content: fullPayload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // MARK: - Shared JSON-RPC 2.0 Dispatcher (HTTP & stdio CLI)
    public func handleJSONRPCRequest(
        bodyData: Data,
        authHeader: String? = nil,
        clientHint: String? = nil,
        bypassAuth: Bool = false
    ) -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return makeErrorResponse(id: nil, code: -32700, message: "Parse error")
        }

        let requestID = json["id"]
        let method = json["method"] as? String ?? ""
        let params = json["params"] as? [String: Any] ?? [:]

        // Check bearer token if provided or required
        if !bypassAuth, let authHeader = authHeader, !authHeader.isEmpty {
            let token = authHeader.replacingOccurrences(of: "Bearer ", with: "").trimmingCharacters(in: .whitespaces)
            if token != settings.mcpAuthToken {
                return makeErrorResponse(id: requestID, code: -32001, message: "Invalid Void MCP bearer token")
            }
        }

        // Record client activity
        if let hint = clientHint {
            recordClientTouch(hint: hint, params: params)
        }

        switch method {
        case "initialize":
            let clientInfo = params["clientInfo"] as? [String: Any]
            if let clientName = clientInfo?["name"] as? String {
                recordClientTouch(hint: clientName, params: params)
            }
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": true]
                ],
                "serverInfo": [
                    "name": "void-mcp",
                    "version": "1.0.0"
                ]
            ]
            return makeSuccessResponse(id: requestID, result: result)

        case "notifications/initialized":
            return makeSuccessResponse(id: requestID, result: [:])

        case "ping":
            return makeSuccessResponse(id: requestID, result: [:])

        case "tools/list":
            return makeSuccessResponse(id: requestID, result: ["tools": Self.toolDefinitions])

        case "tools/call":
            guard let toolName = params["name"] as? String else {
                return makeErrorResponse(id: requestID, code: -32602, message: "Missing tool name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let toolResult = executeTool(name: toolName, arguments: args)
            return makeSuccessResponse(id: requestID, result: toolResult)

        default:
            return makeErrorResponse(id: requestID, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func executeTool(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "search_clipboard":
            var filter = SearchFilterState()
            filter.query = arguments["query"] as? String ?? ""
            if let typeStr = arguments["content_type"] as? String,
               let cType = ClipboardContentType(rawValue: typeStr.lowercased()) {
                filter.contentTypes.insert(cType)
            }
            if let app = arguments["source_app"] as? String, !app.isEmpty {
                filter.sourceApps.insert(app)
            }
            if let pid = arguments["pinboard_id"] as? String, !pid.isEmpty {
                filter.pinboardIDs.insert(pid)
            }
            if let dr = arguments["date_range"] as? String,
               let range = DateRangeFilter.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(dr) == .orderedSame }) {
                filter.dateRange = range
            }
            let limit = arguments["limit"] as? Int ?? 25
            let items = database.searchItems(filter: filter, limit: limit)
            return formatToolOutput(items.map(serializeItem))

        case "get_recent_items":
            let limit = arguments["limit"] as? Int ?? 20
            let pinboardID = arguments["pinboard_id"] as? String
            let items = database.fetchItems(pinboardID: pinboardID, limit: limit)
            return formatToolOutput(items.map(serializeItem))

        case "get_clipboard_item":
            guard let id = arguments["id"] as? String,
                  let item = database.fetchItem(id: id) else {
                return formatToolError("Item not found")
            }
            var dict = serializeItem(item)
            if (arguments["include_image_base64"] as? Bool) == true,
               let hash = item.imageAssetHash,
               let data = assetStore.loadData(forHash: hash) {
                dict["image_base64"] = data.base64EncodedString()
            }
            return formatToolOutput(dict)

        case "create_clipboard_item":
            guard let text = arguments["text"] as? String, !text.isEmpty else {
                return formatToolError("Missing required parameter 'text'")
            }
            let title = arguments["title"] as? String
            let pinboardID = arguments["pinboard_id"] as? String
            var item = PayloadClassifier.classifyString(
                text,
                title: title,
                sourceAppBundleID: "com.voidapp.mcp",
                sourceAppName: "Void MCP",
                sourceAppColorHex: "#FF9400",
                assetStore: assetStore
            )
            item.pinboardID = pinboardID
            let saved = database.insertOrPromoteItem(item, deduplicateConsecutive: false)
            notifyMutation()
            return formatToolOutput(serializeItem(saved))

        case "list_pinboards":
            let boards = database.fetchPinboards().map { board -> [String: Any] in
                [
                    "id": board.id,
                    "name": board.name,
                    "color_hex": board.colorHex,
                    "sort_order": board.sortOrder
                ]
            }
            return formatToolOutput(boards)

        case "create_pinboard":
            guard let boardName = arguments["name"] as? String, !boardName.isEmpty else {
                return formatToolError("Missing required parameter 'name'")
            }
            let colorHex = arguments["color_hex"] as? String ?? "#FF9400"
            let nextOrder = (database.fetchPinboards().map(\.sortOrder).max() ?? -1) + 1
            let board = Pinboard(name: boardName, colorHex: colorHex, sortOrder: nextOrder)
            database.savePinboard(board)
            notifyMutation()
            return formatToolOutput([
                "id": board.id,
                "name": board.name,
                "color_hex": board.colorHex,
                "sort_order": board.sortOrder
            ])

        case "pin_items":
            guard let itemIDs = arguments["item_ids"] as? [String] else {
                return formatToolError("Missing 'item_ids' array")
            }
            let pinboardID = arguments["pinboard_id"] as? String
            for id in itemIDs {
                database.pinItem(id: id, toPinboardID: pinboardID)
            }
            notifyMutation()
            return formatToolOutput(["pinned_count": itemIDs.count, "pinboard_id": pinboardID as Any])

        case "delete_clipboard_items":
            guard let itemIDs = arguments["item_ids"] as? [String] else {
                return formatToolError("Missing 'item_ids' array")
            }
            database.deleteItems(ids: itemIDs)
            notifyMutation()
            return formatToolOutput(["deleted_count": itemIDs.count])

        default:
            return formatToolError("Unknown tool '\(name)'")
        }
    }

    private func notifyMutation() {
        DispatchQueue.main.async { [weak self] in
            self?.onDataMutated?()
        }
    }

    private func serializeItem(_ item: ClipboardItem) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id,
            "content_type": item.contentType.rawValue,
            "title": item.displayHeaderTitle,
            "char_count": item.charCount,
            "word_count": item.wordCount,
            "line_count": item.lineCount,
            "last_copied_at": ISO8601DateFormatter().string(from: item.lastCopiedAt),
            "relative_time": item.relativeTimeString
        ]
        if let text = item.plainText { dict["plain_text"] = text }
        if let url = item.urlString { dict["url"] = url }
        if let color = item.colorHex { dict["color_hex"] = color }
        if let ocr = item.ocrText { dict["ocr_text"] = ocr }
        if !item.fileURLs.isEmpty { dict["file_urls"] = item.fileURLs }
        if let app = item.sourceAppName { dict["source_app"] = app }
        if let pid = item.pinboardID { dict["pinboard_id"] = pid }
        return dict
    }

    private func formatToolOutput(_ payload: Any) -> [String: Any] {
        let jsonData = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let text = String(data: jsonData, encoding: .utf8) ?? "{}"
        return [
            "content": [
                ["type": "text", "text": text]
            ],
            "isError": false
        ]
    }

    private func formatToolError(_ message: String) -> [String: Any] {
        return [
            "content": [
                ["type": "text", "text": message]
            ],
            "isError": true
        ]
    }

    private func recordClientTouch(hint: String, params: [String: Any]) {
        let lower = hint.lowercased()
        let detectedType: MCPClientType
        if lower.contains("claude-code") || lower.contains("claude code") {
            detectedType = .claudeCode
        } else if lower.contains("claude") {
            detectedType = .claudeDesktop
        } else if lower.contains("codex") {
            detectedType = .codex
        } else if lower.contains("cursor") {
            detectedType = .cursor
        } else if lower.contains("vscode") || lower.contains("visual studio") {
            detectedType = .vscode
        } else if lower.contains("windsurf") {
            detectedType = .windsurf
        } else {
            detectedType = .custom
        }
        _ = registerOrConnectClient(type: detectedType, customName: detectedType == .custom ? hint : detectedType.rawValue)
    }

    private func makeSuccessResponse(id: Any?, result: [String: Any]) -> Data {
        var resp: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        resp["id"] = id ?? NSNull()
        return (try? JSONSerialization.data(withJSONObject: resp)) ?? Data()
    }

    private func makeErrorResponse(id: Any?, code: Int, message: String) -> Data {
        var resp: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ]
        ]
        resp["id"] = id ?? NSNull()
        return (try? JSONSerialization.data(withJSONObject: resp)) ?? Data()
    }

    public static let toolDefinitions: [[String: Any]] = [
        [
            "name": "search_clipboard",
            "description": "Search Void clipboard history and pinboards using full-text FTS5 (including OCR text inside images) and smart filters.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query string"],
                    "content_type": ["type": "string", "description": "Filter by type: text, link, image, file, color, code"],
                    "source_app": ["type": "string", "description": "Filter by source application name or bundle ID"],
                    "pinboard_id": ["type": "string", "description": "Filter by pinboard ID"],
                    "date_range": ["type": "string", "description": "Today, Yesterday, Last 7 Days, Last Week, Last Month"],
                    "limit": ["type": "integer", "description": "Maximum results to return"]
                ]
            ]
        ],
        [
            "name": "get_recent_items",
            "description": "Retrieve the most recent clipboard items or items inside a specific Pinboard.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Number of items to return (default 20)"],
                    "pinboard_id": ["type": "string", "description": "Optional Pinboard ID"]
                ]
            ]
        ],
        [
            "name": "get_clipboard_item",
            "description": "Retrieve full details and metadata for a single clipboard item by ID.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Clipboard item ID"],
                    "include_image_base64": ["type": "boolean", "description": "Include base64 PNG payload for image items"]
                ],
                "required": ["id"]
            ]
        ],
        [
            "name": "create_clipboard_item",
            "description": "Create a new item in Void clipboard history and optionally pin it to a Pinboard.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text, code, URL, or color hex content"],
                    "title": ["type": "string", "description": "Optional custom card title"],
                    "pinboard_id": ["type": "string", "description": "Optional target Pinboard ID"]
                ],
                "required": ["text"]
            ]
        ],
        [
            "name": "list_pinboards",
            "description": "List all Pinboards in Void with their IDs, names, and colors.",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any]
            ]
        ],
        [
            "name": "create_pinboard",
            "description": "Create a new color-coded Pinboard.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Pinboard name"],
                    "color_hex": ["type": "string", "description": "Hex color code, e.g. #FF9400"]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "pin_items",
            "description": "Pin or unpin clipboard items to a Pinboard (single-pinboard-per-item semantics).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "item_ids": ["type": "array", "items": ["type": "string"]],
                    "pinboard_id": ["type": "string", "description": "Target Pinboard ID, or omit/null to unpin"]
                ],
                "required": ["item_ids"]
            ]
        ],
        [
            "name": "delete_clipboard_items",
            "description": "Delete specified clipboard items by ID.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "item_ids": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["item_ids"]
            ]
        ]
    ]
}
