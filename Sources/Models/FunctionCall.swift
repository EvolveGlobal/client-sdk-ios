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
    public let name: String
    public let parameters: [String: Any]
    
    public init(name: String, parameters: [String: Any]) {
        self.name = name
        self.parameters = parameters
    }
    
    // Custom coding implementation to handle [String: Any] parameters
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
        try container.encode(name, forKey: .name)
        try container.encode(AnyCodable(parameters), forKey: .parameters)
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case parameters
    }
}

// Model for the complete function call message structure
public struct FunctionCallMessage: Codable {
    public let type: String
    public let functionCall: FunctionCall
}

// Model for tool call item (used in both model-output and tool-calls messages)
public struct ToolCallItem: Codable {
    public let id: String
    public let type: String
    public let function: ToolCallFunction
    public let isPrecededByText: Bool?
    
    public struct ToolCallFunction: Codable {
        public let name: String
        public let arguments: AnyCodable
        
        // Convert arguments to our FunctionCall format
        public func toFunctionCall() throws -> FunctionCall {
            let parameters: [String: Any]
            
            switch arguments.value {
            case let dict as [String: Any]:
                // Arguments is already a dictionary
                parameters = dict
            case let string as String:
                // Arguments is a JSON string - need to parse it
                if string.isEmpty || string == "{}" {
                    parameters = [:]
                } else {
                    let data = string.data(using: .utf8) ?? Data()
                    if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        parameters = jsonObject
                    } else {
                        // If parsing fails, treat as empty parameters
                        print("Warning: Could not parse function arguments JSON: \(string)")
                        parameters = [:]
                    }
                }
            case is NSNull:
                // Handle null case
                parameters = [:]
            default:
                // Handle any other case
                print("Warning: Unexpected function arguments type: \(Swift.type(of: arguments.value))")
                parameters = [:]
            }
            
            return FunctionCall(name: name, parameters: parameters)
        }
    }
}

// Model for model-output messages that contain function calls
public struct ModelOutputMessage: Codable {
    public let type: String
    public let output: [ToolCallItem]
}

// Model for tool-calls messages  
public struct ToolCallsMessage: Codable {
    public let type: String
    public let toolCalls: [ToolCallItem]
    
    // Optional additional fields that might be present
    public let toolCallList: [ToolCallItem]?
    public let toolWithToolCallList: [ToolWithCallItem]?
    
    // Additional tool call structure for toolWithToolCallList
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
