import Foundation
import VoidCore

// void-mcp: Stdio Model Context Protocol (MCP) Server for Void
// Reads newline-delimited JSON-RPC 2.0 messages from stdin and writes JSON-RPC 2.0 responses to stdout.

let mcpService = MCPServerService(
    database: DatabaseManager(seedIfEmpty: false),
    assetStore: .shared,
    settings: .shared
)

let envToken = ProcessInfo.processInfo.environment["VOID_MCP_TOKEN"]
let authHeader = envToken.map { "Bearer \($0)" }

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }
    let requestData = Data(trimmed.utf8)
    let responseData = mcpService.handleJSONRPCRequest(
        bodyData: requestData,
        authHeader: authHeader,
        clientHint: "void-mcp-stdio",
        bypassAuth: envToken == nil
    )
    if let responseString = String(data: responseData, encoding: .utf8), !responseString.isEmpty {
        FileHandle.standardOutput.write(Data((responseString + "\n").utf8))
    }
}
