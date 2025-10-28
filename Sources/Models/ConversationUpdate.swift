import Foundation

public struct Message: Codable {
    public enum Role: String, Codable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
        case tool = "tool"
        // CHANGE: Added unknown case to handle unexpected/missing role values
        // WHY: Prevents decoding failures if Vapi adds new role types or omits the role field.
        // All invalid/missing roles default to .unknown instead of failing the entire message
        case unknown = "unknown"
    }
    
    // CHANGE: Role is non-optional but defaults to .unknown for invalid/missing values
    // WHY: Simpler for consumers (no need to unwrap optionals) while still handling
    // missing or unrecognized roles gracefully
    public let role: Role
    public let content: String?
    // CHANGE: Added toolCalls field to parse function calls from conversation history
    // WHY: Vapi includes tool_calls in conversation-update messages for tracking assistant function invocations
    public let toolCalls: [ToolCallItem]?
    public let toolCallId: String?
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
    
    // CHANGE: Added custom decoding to gracefully handle missing or unknown roles
    // WHY: Default Codable decoding would fail the entire message if role is invalid/missing.
    // Custom decoding falls back to .unknown, allowing parsing to continue
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode role, fall back to .unknown if missing or unrecognized
        if let roleString = try? container.decode(String.self, forKey: .role),
           let decodedRole = Role(rawValue: roleString) {
            role = decodedRole
        } else {
            // Default to .unknown for missing or unrecognized roles
            role = .unknown
        }
        
        content = try container.decodeIfPresent(String.self, forKey: .content)
        toolCalls = try container.decodeIfPresent([ToolCallItem].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
    }
}

public struct ConversationUpdate: Codable {
    // CHANGE: Modified to parse conversation history containing tool calls
    // WHY: We extract function calls from the conversation array (which is [Message]).
    // The Message struct was enhanced to include toolCalls field for function call extraction
    public let conversation: [Message]
}
