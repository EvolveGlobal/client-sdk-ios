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
}
