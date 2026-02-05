//
//  AppMessage.swift
//  
//
//  Created by Brent Whitman on 2024-01-15.
//

import Foundation

struct AppMessage: Codable {
    enum MessageType: String, Codable {
        case hang
        
        // LEGACY: Kept for backward compatibility with older Vapi versions
        // Current Vapi implementations use toolCalls, modelOutput, and conversationUpdate instead
        case functionCall = "function-call"
        
        case transcript
        case speechUpdate = "speech-update"
        case metadata
        case conversationUpdate = "conversation-update"
        case modelOutput = "model-output"
        case statusUpdate = "status-update"
        case voiceInput = "voice-input"
        case userInterrupted = "user-interrupted"
        
        // CHANGE: Added to support tool-calls message type from Vapi (PRIMARY FORMAT)
        // WHY: Vapi sends function calls via "tool-calls" messages as the primary format,
        // and also via "model-output" and "conversation-update" messages
        case toolCalls = "tool-calls"
    }
    
    let type: MessageType
}
