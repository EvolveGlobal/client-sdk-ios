//
//  FunctionCall.swift
//
//
//  Created by Brent Whitman on 2024-01-15.
//

import Foundation

// Helper struct for encoding/decoding Any values
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

// Model for the complete function call message structure
public struct FunctionCallMessage: Codable {
    public let type: String
    public let functionCall: FunctionCall
}

// CHANGE: Added ToolCallItem model to parse tool calls from Vapi messages
// WHY: Vapi sends tool calls in multiple message formats (model-output, tool-calls, conversation-update)
// that use a nested structure different from the direct function-call message format
public struct ToolCallItem: Codable {
    public let id: String
    public let type: String
    public let function: ToolCallFunction
    public let isPrecededByText: Bool?
    
    /// Converts the ToolCallItem to a standardized FunctionCall
    /// WHY: Unifies different message formats into a single FunctionCall event for the app
    public func toFunctionCall() throws -> FunctionCall {
        let parameters: [String: Any]
        
        // CHANGE: Made arguments optional to handle cases where function has no parameters
        // WHY: Vapi sometimes omits the arguments field entirely for parameterless functions
        guard let arguments = function.arguments else {
            return FunctionCall(id: id, name: function.name, parameters: [:])
        }
        
        // CHANGE: Handle multiple argument formats (dictionary, JSON string, null)
        // WHY: Vapi inconsistently sends arguments as either:
        // - A dictionary: {"key": "value"}
        // - A JSON string: "{\"key\":\"value\"}" or "{}"
        // - Null/omitted entirely
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
        
        return FunctionCall(id: id, name: function.name, parameters: parameters)
    }
    
    public struct ToolCallFunction: Codable {
        public let name: String
        // CHANGE: Made arguments optional (AnyCodable?)
        // WHY: Vapi may omit the arguments field for functions with no parameters
        public let arguments: AnyCodable?
        
        /// Converts to FunctionCall format without an ID (for legacy compatibility)
        public func toFunctionCall() throws -> FunctionCall {
            let parameters: [String: Any]
            
            guard let arguments = arguments else {
                return FunctionCall(name: name, parameters: [:])
            }
            
            // Same argument parsing logic as ToolCallItem.toFunctionCall()
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
                        parameters = [:]
                    }
                }
            case is NSNull:
                parameters = [:]
            default:
                parameters = [:]
            }
            
            return FunctionCall(name: name, parameters: parameters)
        }
    }
}

// CHANGE: Added ModelOutputMessage to parse model-output messages from Vapi
// WHY: Vapi sends function calls in "model-output" messages with an "output" array of ToolCallItems
public struct ModelOutputMessage: Codable {
    public let type: String
    public let output: [ToolCallItem]
}

// CHANGE: Added ToolCallsMessage to parse tool-calls messages from Vapi
// WHY: Vapi sends function calls in "tool-calls" messages with a "toolCalls" array
public struct ToolCallsMessage: Codable {
    public let type: String
    public let toolCalls: [ToolCallItem]
    
    // CHANGE: Added optional fields for comprehensive message parsing
    // WHY: Vapi messages may include additional metadata fields. Making them optional
    // allows parsing to succeed even when these fields are missing
    public let toolCallList: [ToolCallItem]?
    public let toolWithToolCallList: [ToolWithCallItem]?
    
    /// Additional tool call metadata structure that may be present in some messages
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
