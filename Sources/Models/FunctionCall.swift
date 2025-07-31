//
//  FunctionCall.swift
//
//
//  Created by Brent Whitman on 2024-01-15.
//

import Foundation

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
        
        // Decode parameters as a generic JSON object
        let parametersContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .parameters)
        var decodedParameters: [String: Any] = [:]
        
        for key in parametersContainer.allKeys {
            if let stringValue = try? parametersContainer.decode(String.self, forKey: key) {
                decodedParameters[key.stringValue] = stringValue
            } else if let intValue = try? parametersContainer.decode(Int.self, forKey: key) {
                decodedParameters[key.stringValue] = intValue
            } else if let doubleValue = try? parametersContainer.decode(Double.self, forKey: key) {
                decodedParameters[key.stringValue] = doubleValue
            } else if let boolValue = try? parametersContainer.decode(Bool.self, forKey: key) {
                decodedParameters[key.stringValue] = boolValue
            } else {
                // Handle nested objects/arrays as raw JSON
                let jsonValue = try parametersContainer.decode(AnyCodable.self, forKey: key)
                decodedParameters[key.stringValue] = jsonValue.value
            }
        }
        
        parameters = decodedParameters
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        
        var parametersContainer = encoder.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .parameters)
        
        for (key, value) in parameters {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            let anyCodable = AnyCodable(value)
            try parametersContainer.encode(anyCodable, forKey: codingKey)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case parameters
    }
    
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            return nil
        }
    }
    
    struct AnyCodable: Codable {
        let value: Any
        
        init(_ value: Any) {
            self.value = value
        }
        
        init(from decoder: Decoder) throws {
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
            } else {
                throw DecodingError.typeMismatch(Any.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
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
            default:
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
            }
        }
    }
}

// Model for the complete function call message structure
public struct FunctionCallMessage: Codable {
    public let type: String
    public let functionCall: FunctionCall
}
