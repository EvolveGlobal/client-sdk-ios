//
//  VapiTests.swift
//
//
//  Created by Brent Whitman on 2024-01-15.
//

import XCTest
@testable import Vapi

final class VapiTests: XCTestCase {
    
    func testFunctionCallParsing() throws {
        // Example JSON structure based on Vapi webhook documentation
        let functionCallJSON = """
        {
            "type": "function-call",
            "functionCall": {
                "name": "sendEmail",
                "parameters": {
                    "to": "user@example.com",
                    "subject": "Test Email",
                    "body": "This is a test email",
                    "priority": 1,
                    "isUrgent": true
                }
            }
        }
        """
        
        let jsonData = functionCallJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        // Test that we can decode the FunctionCallMessage correctly
        let functionCallMessage = try decoder.decode(FunctionCallMessage.self, from: jsonData)
        
        XCTAssertEqual(functionCallMessage.type, "function-call")
        XCTAssertEqual(functionCallMessage.functionCall.name, "sendEmail")
        
        // Test parameters
        let parameters = functionCallMessage.functionCall.parameters
        XCTAssertEqual(parameters["to"] as? String, "user@example.com")
        XCTAssertEqual(parameters["subject"] as? String, "Test Email")
        XCTAssertEqual(parameters["body"] as? String, "This is a test email")
        XCTAssertEqual(parameters["priority"] as? Int, 1)
        XCTAssertEqual(parameters["isUrgent"] as? Bool, true)
    }
    
    func testModelOutputFunctionCallParsing() throws {
        // Test model-output message format with function calls
        let modelOutputJSON = """
        {
            "type": "model-output",
            "output": [
                {
                    "id": "call_123",
                    "type": "function",
                    "function": {
                        "name": "showSleepCoachInstructions",
                        "arguments": "{}"
                    }
                }
            ]
        }
        """
        
        let jsonData = modelOutputJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        let modelOutputMessage = try decoder.decode(ModelOutputMessage.self, from: jsonData)
        
        XCTAssertEqual(modelOutputMessage.type, "model-output")
        XCTAssertEqual(modelOutputMessage.output.count, 1)
        
        let toolCall = modelOutputMessage.output[0]
        XCTAssertEqual(toolCall.id, "call_123")
        XCTAssertEqual(toolCall.type, "function")
        XCTAssertEqual(toolCall.function.name, "showSleepCoachInstructions")
        
        // Test conversion to FunctionCall
        let functionCall = try toolCall.function.toFunctionCall()
        XCTAssertEqual(functionCall.name, "showSleepCoachInstructions")
        XCTAssertTrue(functionCall.parameters.isEmpty)
    }
    
    func testToolCallsMessageParsing() throws {
        // Test tool-calls message format
        let toolCallsJSON = """
        {
            "type": "tool-calls",
            "toolCalls": [
                {
                    "id": "call_456",
                    "type": "function",
                    "function": {
                        "name": "getUserPreferences",
                        "arguments": {
                            "userId": "123",
                            "includePrivate": true
                        }
                    }
                }
            ]
        }
        """
        
        let jsonData = toolCallsJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        let toolCallsMessage = try decoder.decode(ToolCallsMessage.self, from: jsonData)
        
        XCTAssertEqual(toolCallsMessage.type, "tool-calls")
        XCTAssertEqual(toolCallsMessage.toolCalls.count, 1)
        
        let toolCall = toolCallsMessage.toolCalls[0]
        XCTAssertEqual(toolCall.id, "call_456")
        XCTAssertEqual(toolCall.type, "function")
        XCTAssertEqual(toolCall.function.name, "getUserPreferences")
        
        // Test conversion to FunctionCall
        let functionCall = try toolCall.function.toFunctionCall()
        XCTAssertEqual(functionCall.name, "getUserPreferences")
        XCTAssertEqual(functionCall.parameters["userId"] as? String, "123")
        XCTAssertEqual(functionCall.parameters["includePrivate"] as? Bool, true)
    }
    
    func testAppMessageTypeParsing() throws {
        // Test that the AppMessage correctly identifies function-call type
        let appMessageJSON = """
        {
            "type": "function-call"
        }
        """
        
        let jsonData = appMessageJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        let appMessage = try decoder.decode(AppMessage.self, from: jsonData)
        XCTAssertEqual(appMessage.type, .functionCall)
    }
    
    func testAppMessageToolCallsTypeParsing() throws {
        // Test that the AppMessage correctly identifies tool-calls type
        let appMessageJSON = """
        {
            "type": "tool-calls"
        }
        """
        
        let jsonData = appMessageJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        let appMessage = try decoder.decode(AppMessage.self, from: jsonData)
        XCTAssertEqual(appMessage.type, .toolCalls)
    }
}
