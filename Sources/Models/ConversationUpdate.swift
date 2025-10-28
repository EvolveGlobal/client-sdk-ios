import Foundation

public struct Message: Codable {
    public enum Role: String, Codable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
        case tool = "tool"
        // CHANGE: Added unknown case to handle unexpected role values
        // WHY: Prevents decoding failures if Vapi adds new role types in the future
        case unknown = "unknown"
    }
    
    // CHANGE: Made role optional (Role?)
    // WHY: Vapi may send messages without a role field, or with unrecognized role values.
    // Making it optional prevents the entire conversation-update message from failing to parse
    public let role: Role?
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
    // WHY: Default Codable decoding would fail the entire message if role is invalid.
    // Custom decoding allows us to continue parsing even with missing/unknown roles
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode role, fall back to nil if it fails
        if let roleString = try? container.decode(String.self, forKey: .role),
           let decodedRole = Role(rawValue: roleString) {
            role = decodedRole
        } else {
            // Silently handle unknown/missing roles
            role = nil
        }
        
        content = try container.decodeIfPresent(String.self, forKey: .content)
        toolCalls = try container.decodeIfPresent([ToolCallItem].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
    }
}

public struct ConversationMessage: Codable {
    public enum Role: String, Codable {
        case system = "system"
        case bot = "bot"
        case user = "user"
        case toolCalls = "tool_calls"
        case toolCallResult = "tool_call_result"
    }
    
    public let role: Role
    public let message: String?
    public let time: Double?
    public let endTime: Double?
    public let secondsFromStart: Double?
    public let duration: Double?
    public let source: String?
    public let toolCalls: [ToolCallItem]?
    public let name: String?
    public let result: String?
    public let toolCallId: String?
    

}

public struct ConversationUpdate: Codable {
    public let conversation: [Message]
    public let messages: [ConversationMessage]?
    public let messagesOpenAIFormatted: [AnyCodable]?
}
