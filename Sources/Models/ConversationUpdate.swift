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
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        toolCalls = try container.decodeIfPresent([ToolCallItem].self, forKey: .toolCalls)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
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
    
    enum CodingKeys: String, CodingKey {
        case role
        case message
        case time
        case endTime
        case secondsFromStart
        case duration
        case source
        case toolCalls
        case name
        case result
        case toolCallId
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(Role.self, forKey: .role)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        time = try container.decodeIfPresent(Double.self, forKey: .time)
        endTime = try container.decodeIfPresent(Double.self, forKey: .endTime)
        secondsFromStart = try container.decodeIfPresent(Double.self, forKey: .secondsFromStart)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        toolCalls = try container.decodeIfPresent([ToolCallItem].self, forKey: .toolCalls)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
    }
}

public struct ConversationUpdate: Codable {
    public let conversation: [Message]
    public let messages: [ConversationMessage]?
    public let messagesOpenAIFormatted: [AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case conversation
        case messages
        case messagesOpenAIFormatted
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversation = try container.decode([Message].self, forKey: .conversation)
        messages = try container.decodeIfPresent([ConversationMessage].self, forKey: .messages)
        messagesOpenAIFormatted = try container.decodeIfPresent([AnyCodable].self, forKey: .messagesOpenAIFormatted)
    }
}
