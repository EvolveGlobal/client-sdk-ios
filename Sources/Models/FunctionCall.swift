//
//  FunctionCall.swift
//
//
//  Created by Brent Whitman on 2024-01-15.
//

import Foundation

// MARK: - Shared Helper

/// Helper struct for encoding/decoding Any values used across function/tool call parsing
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.typeMismatch(Any.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let stringValue as String:
            try container.encode(stringValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            let anyCodableArray = arrayValue.map { AnyCodable($0) }
            try container.encode(anyCodableArray)
        case let dictionaryValue as [String: Any]:
            let anyCodableDictionary = dictionaryValue.mapValues { AnyCodable($0) }
            try container.encode(anyCodableDictionary)
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - Legacy Format Model

/// LEGACY: Represents a function call from old "function-call" messages
/// Kept for backward compatibility with older Vapi versions
public struct FunctionCall: Codable {
    public let id: String?
    public let name: String
    public let parameters: [String: Any]
    
    public init(id: String? = nil, name: String, parameters: [String: Any]) {
        self.id = id
        self.name = name
        self.parameters = parameters
    }
    
    // Custom coding implementation to handle [String: Any] parameters
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        // Decode parameters as AnyCodable and convert
        if let parametersValue = try? container.decode(AnyCodable.self, forKey: .parameters) {
            if let dict = parametersValue.value as? [String: Any] {
                parameters = dict
            } else {
                parameters = [:]
            }
        } else {
            parameters = [:]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(AnyCodable(parameters), forKey: .parameters)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parameters
    }
}

// MARK: - Modern Format Model

/// Represents a tool call from modern Vapi formats (model-output, tool-calls, conversation-update)
/// This is the current/active format used by Vapi
public struct ToolCall: Codable {
    public let id: String
    public let name: String
    public let parameters: [String: Any]
    
    public init(id: String, name: String, parameters: [String: Any]) {
        self.id = id
        self.name = name
        self.parameters = parameters
    }
    
    // Custom coding implementation to handle [String: Any] parameters
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        // Decode parameters as AnyCodable and convert
        if let parametersValue = try? container.decode(AnyCodable.self, forKey: .parameters) {
            if let dict = parametersValue.value as? [String: Any] {
                parameters = dict
            } else {
                parameters = [:]
            }
        } else {
            parameters = [:]
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(AnyCodable(parameters), forKey: .parameters)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parameters
    }
}

// MARK: - Legacy Format (function-call message)

/// LEGACY: Model for direct "function-call" message type
/// Current Vapi versions use tool-calls, model-output, and conversation-update instead
/// Kept for backward compatibility with older Vapi versions
public struct FunctionCallMessage: Codable {
    public let type: String
    public let functionCall: FunctionCall
}

// MARK: - Modern Tool Call Formats

/// Represents a tool call item from Vapi's modern message formats
/// Used in: model-output, tool-calls, and conversation-update messages
/// WHY: Vapi's modern formats use a nested structure different from legacy function-call messages
public struct ToolCallItem: Codable {
    public let id: String
    public let type: String
    public let function: ToolCallFunction
    public let isPrecededByText: Bool?
    
    /// Converts the ToolCallItem to a ToolCall
    /// This normalizes the nested tool call structure from Vapi into a clean model
    public func toToolCall() throws -> ToolCall {
        let parameters: [String: Any]
        
        // Handle optional arguments (may be missing for parameterless functions)
        guard let arguments = function.arguments else {
            return ToolCall(id: id, name: function.name, parameters: [:])
        }
        
        // Parse arguments which can be in multiple formats:
        // - Dictionary: {"key": "value"}
        // - JSON string: "{\"key\":\"value\"}" or "{}"
        // - Null value
        switch arguments.value {
        case let dict as [String: Any]:
            parameters = dict
        case let string as String:
            if string.isEmpty || string == "{}" {
                parameters = [:]
            } else {
                let data = string.data(using: .utf8) ?? Data()
                if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    parameters = jsonObject
                } else {
                    // Silently fall back to empty parameters if parsing fails
                    parameters = [:]
                }
            }
        case is NSNull:
            parameters = [:]
        default:
            parameters = [:]
        }
        
        return ToolCall(id: id, name: function.name, parameters: parameters)
    }
    
    /// Nested function details within a ToolCallItem
    /// To convert to ToolCall, use ToolCallItem.toToolCall()
    public struct ToolCallFunction: Codable {
        public let name: String
        /// Optional arguments - may be omitted for parameterless functions
        public let arguments: AnyCodable?
    }
}

/// Message format for "model-output" type containing tool calls
/// Vapi sends tool calls in model-output messages with an "output" array
public struct ModelOutputMessage: Codable {
    public let type: String
    public let output: [ToolCallItem]
}

/// Message format for "tool-calls" type (PRIMARY modern format)
/// Vapi's main way of sending tool calls
public struct ToolCallsMessage: Codable {
    public let type: String
    public let toolCalls: [ToolCallItem]
    
    // Optional additional fields that may be present in some messages
    // Making them optional allows parsing to succeed even when missing
    public let toolCallList: [ToolCallItem]?
    public let toolWithToolCallList: [ToolWithCallItem]?
    
    /// Additional tool call metadata that may be included in some messages
    public struct ToolWithCallItem: Codable {
        public let type: String?
        public let function: ToolFunctionDefinition?
        public let messages: [ToolMessage]?
        public let toolCall: ToolCallItem?
        
        public struct ToolFunctionDefinition: Codable {
            public let name: String?
            public let parameters: AnyCodable?
            public let description: String?
        }
        
        public struct ToolMessage: Codable {
            public let type: String?
            public let content: String?
            public let contents: [AnyCodable]?
            public let conditions: [AnyCodable]?
            public let blocking: Bool?
        }
    }
}
