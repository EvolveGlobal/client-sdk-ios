import Foundation

public struct Message: Codable {
    public enum Role: String, Codable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
        case tool = "tool"
    }
    
    public let role: Role
    public let content: String?
    public let toolCalls: [ToolCallItem]?
    public let toolCallId: String?
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
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
