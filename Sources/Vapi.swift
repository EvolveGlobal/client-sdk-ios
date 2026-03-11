import Combine
import Daily
import Foundation

// Define the nested message structure
struct VapiMessageContent: Encodable {
    public let role: String
    public let content: String
}

// Define the top-level app message structure
public struct VapiMessage: Encodable {
    public let type: String
    let message: VapiMessageContent
    public let triggerResponseEnabled: Bool?

    public init(type: String, role: String, content: String, triggerResponseEnabled: Bool? = nil) {
        self.type = type
        self.message = VapiMessageContent(role: role, content: content)
        self.triggerResponseEnabled = triggerResponseEnabled
    }
}

// Define the function call response structure
public struct VapiFunctionCallResponse: Encodable {
    public let type: String
    public let toolCallId: String
    public let result: String
    
    public init(toolCallId: String, result: String) {
        self.type = "function-call-result"
        self.toolCallId = toolCallId
        self.result = result
    }
}

public final class Vapi: CallClientDelegate {
    
    // MARK: - Supporting Types
    
    /// A configuration that contains the host URL and the client token.
    ///
    /// This configuration is serializable via `Codable`.
    public struct Configuration: Codable, Hashable, Sendable {
        public var host: String
        public var publicKey: String
        fileprivate static let defaultHost = "api.vapi.ai"
        
        init(publicKey: String, host: String) {
            self.host = host
            self.publicKey = publicKey
        }
    }

    public enum Event {
        case callDidStart
        case callDidEnd
        case transcript(Transcript)
        
        // LEGACY: Direct function-call messages (kept for backward compatibility)
        case functionCall(FunctionCall)
        
        // NEW: Tool calls from model-output, tool-calls, and conversation-update messages
        case toolCall(ToolCall)
        
        case speechUpdate(SpeechUpdate)
        case metadata(Metadata)
        case conversationUpdate(ConversationUpdate)
        case statusUpdate(StatusUpdate)
        case modelOutput(ModelOutput)
        case userInterrupted(UserInterrupted)
        case voiceInput(VoiceInput)
        case hang
        case error(Swift.Error)
    }
    
    // MARK: - Properties

    public let configuration: Configuration

    fileprivate let eventSubject = PassthroughSubject<Event, Never>()
    
    private let networkManager = NetworkManager()
    private var call: CallClient?
    
    // MARK: - Computed Properties
    
    private var publicKey: String {
        configuration.publicKey
    }
    
    /// A Combine publisher that clients can subscribe to for API events.
    public var eventPublisher: AnyPublisher<Event, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    @MainActor public var localAudioLevel: Float? {
        call?.localAudioLevel
    }
    
    @MainActor public var remoteAudioLevel: Float? {
        call?.remoteParticipantsAudioLevel.values.first
    }
    
    @MainActor public var audioDeviceType: AudioDeviceType? {
        call?.audioDevice
    }
    
    private var isMicrophoneMuted: Bool = false
    private var isAssistantMuted: Bool = false
    
    // MARK: - Init
    
    public init(configuration: Configuration) {
        self.configuration = configuration
        
        Daily.setLogLevel(.off)
    }
    
    public convenience init(publicKey: String) {
        self.init(configuration: .init(publicKey: publicKey, host: Configuration.defaultHost))
    }
    
    public convenience init(publicKey: String, host: String? = nil) {
        self.init(configuration: .init(publicKey: publicKey, host: host ?? Configuration.defaultHost))
    }
    
    // MARK: - Instance Methods
    
    public func start(
        assistantId: String, metadata: [String: Any] = [:], assistantOverrides: [String: Any] = [:]
    ) async throws -> WebCallResponse {
        guard self.call == nil else {
            throw VapiError.existingCallInProgress
        }
        
        let body = [
            "assistantId": assistantId, "metadata": metadata, "assistantOverrides": assistantOverrides
        ] as [String: Any]
        
        return try await self.startCall(body: body)
    }
    
    public func start(
        assistant: [String: Any], metadata: [String: Any] = [:], assistantOverrides: [String: Any] = [:]
    ) async throws -> WebCallResponse {
        guard self.call == nil else {
            throw VapiError.existingCallInProgress
        }
        
        let body = [
            "assistant": assistant, "metadata": metadata, "assistantOverrides": assistantOverrides
        ] as [String: Any]

        return try await self.startCall(body: body)
    }
    
    public func stop() {
        Task {
            do {
                try await call?.leave()
                call = nil
            } catch {
                self.callDidFail(with: error)
            }
        }
    }

    public func send(message: VapiMessage) async throws {
        do {
          // Use JSONEncoder to convert the message to JSON Data
          let jsonData = try JSONEncoder().encode(message)
          
          // Debugging: Print the JSON data to verify its format (optional)
          if let jsonString = String(data: jsonData, encoding: .utf8) {
              print(jsonString)
          }
          
          // Send the JSON data to all targets
          try await self.call?.sendAppMessage(json: jsonData, to: .all)
      } catch {
          // Handle encoding error
          print("Error encoding message to JSON: \(error)")
          throw error // Re-throw the error to be handled by the caller
      }
    }

    /// Send a function call response back to the assistant
    /// - Parameters:
    ///   - toolCallId: The ID of the function call (from FunctionCall.id if available, or extract from logs)
    ///   - result: The result to send back (can be "Success", "Error", or a descriptive message)
    public func sendFunctionCallResponse(toolCallId: String, result: String) async throws {
        let response = VapiFunctionCallResponse(toolCallId: toolCallId, result: result)
        
        do {
            let jsonData = try JSONEncoder().encode(response)
            try await self.call?.sendAppMessage(json: jsonData, to: .all)
        } catch {
            throw error
        }
    }

    public func setMuted(_ muted: Bool) async throws {
        guard let call = self.call else {
            throw VapiError.noCallInProgress
        }
        
        do {
            try await call.setInputEnabled(.microphone, !muted)
            self.isMicrophoneMuted = muted
            if muted {
                print("Audio muted")
            } else {
                print("Audio unmuted")
            }
        } catch {
            print("Failed to set mute state: \(error)")
            throw error
        }
    }

    public func isMuted() async throws {
        guard let call = self.call else {
            throw VapiError.noCallInProgress
        }
        
        let shouldBeMuted = !self.isMicrophoneMuted
        
        do {
            try await call.setInputEnabled(.microphone, !shouldBeMuted)
            self.isMicrophoneMuted = shouldBeMuted
            if shouldBeMuted {
                print("Audio muted")
            } else {
                print("Audio unmuted")
            }
        } catch {
            print("Failed to toggle mute state: \(error)")
            throw error
        }
    }
    
    public func setAssistantMuted(_ muted: Bool) async throws {
        guard let call else {
            throw VapiError.noCallInProgress
        }
        
        do {
            let remoteParticipants = await call.participants.remote
            
            // First retrieve the assistant where the user name is "Vapi Speaker", this is the one we will unsubscribe from or subscribe too
            guard let assistant = remoteParticipants.first(where: { $0.value.info.username == .remoteParticipantVapiSpeaker })?.value else { return }
            
            // Then we update the subscription to `staged` if muted which means we don't receive audio
            // but we'll still receive the response. If we unmute it we set it back to `subscribed` so we start
            // receiving audio again. This is taken from Daily examples.
            _ = try await call.updateSubscriptions(
                forParticipants: .set([
                    assistant.id: .set(
                        profile: .set(.base),
                        media: .set(
                            microphone: .set(
                                subscriptionState: muted ? .set(.staged) : .set(.subscribed)
                            )
                        )
                    )
                ])
            )
            isAssistantMuted = muted
        } catch {
            print("Failed to set subscription state to \(muted ? "Staged" : "Subscribed") for remote assistant")
            throw error
        }
    }
    
    /// This method sets the `AudioDeviceType` of the current called to the passed one if it's not the same as the current one
    /// - Parameter audioDeviceType: can either be `bluetooth`, `speakerphone`, `wired` or `earpiece`
    public func setAudioDeviceType(_ audioDeviceType: AudioDeviceType) async throws {
        guard let call else {
            throw VapiError.noCallInProgress
        }
        
        guard await self.audioDeviceType != audioDeviceType else {
            print("Not updating AudioDeviceType because it is the same")
            return
        }
        
        do {
            try await call.setPreferredAudioDevice(audioDeviceType)
        } catch {
            print("Failed to change the AudioDeviceType with error: \(error)")
            throw error
        }
    }

    private func joinCall(url: URL, recordVideo: Bool) {
        Task { @MainActor in
            do {
                let call = CallClient()
                call.delegate = self
                self.call = call
                
                _ = try await call.join(
                    url: url,
                    settings: .init(
                        inputs: .set(
                            camera: .set(.enabled(recordVideo)),
                            microphone: .set(.enabled(true))
                        )
                    )
                )
                
                if(!recordVideo) {
                    return
                }
                    
                _ = try await call.startRecording(
                    streamingSettings: .init(
                        video: .init(
                            width:1280,
                            height:720,
                            backgroundColor: "#FF1F2D3D"
                        )
                    )
                )
            } catch {
                callDidFail(with: error)
            }
        }
    }
    
    private func makeURL(for path: String) -> URL? {
        var components = URLComponents()
        // Check if the host is localhost, set the scheme to http and port to 3001; otherwise, set the scheme to https
        if configuration.host == "localhost" {
            components.scheme = "http"
            components.port = 3001
        } else {
            components.scheme = "https"
        }
        components.host = configuration.host
        components.path = path
        return components.url
    }
    
    private func makeURLRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(publicKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func startCall(body: [String: Any]) async throws -> WebCallResponse {
        guard let url = makeURL(for: "/call/web") else {
            callDidFail(with: VapiError.invalidURL)
            throw VapiError.customError("Unable to create web call")
        }
        
        var request = makeURLRequest(for: url)
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            self.callDidFail(with: error)
            throw VapiError.customError(String(describing: error))
        }
        
        do {
            let response: WebCallResponse = try await networkManager.perform(request: request)
            let isVideoRecordingEnabled = response.artifactPlan?.videoRecordingEnabled ?? false
            joinCall(url: response.webCallUrl, recordVideo: isVideoRecordingEnabled)
            return response
        } catch let vapiError as VapiError {
            callDidFail(with: vapiError)
            throw vapiError
        } catch {
            callDidFail(with: error)
            throw VapiError.customError(String(describing: error))
        }
    }
    
    /// Normalizes app message payload: if it's JSON object/array use as-is; if it's a JSON string (double-encoded) unwrap to inner data.
    /// No sanitization—payloads are valid; we only handle object vs string format.
    /// Uses .fragmentsAllowed so a top-level JSON string (e.g. "{\"type\":\"...\"}") is accepted and unwrapped.
    private func normalizedAppMessageData(_ jsonData: Data) -> (Data, String?) {
        let jsonString = String(data: jsonData, encoding: .utf8)
        guard let parsed = try? JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed) else {
            return (jsonData, jsonString)
        }
        if let innerString = parsed as? String,
           let innerData = innerString.data(using: .utf8) {
            return (innerData, innerString)
        }
        if parsed is [String: Any] || parsed is [Any] {
            return (jsonData, jsonString)
        }
        return (jsonData, jsonString)
    }

    public func startLocalAudioLevelObserver() async throws {
        do {
            try await call?.startLocalAudioLevelObserver()
        } catch {
            throw error
        }
    }
    
    public func startRemoteParticipantsAudioLevelObserver() async throws {
        do {
            try await call?.startRemoteParticipantsAudioLevelObserver()
        } catch {
            throw error
        }
    }
    
    // MARK: - CallClientDelegate
    
    func callDidJoin() {
        print("Successfully joined call.")
        // Note: the call start event will be sent once the assistant has joined and is listening
    }
    
    func callDidLeave() {
        print("Successfully left call.")
        
        self.eventSubject.send(.callDidEnd)
        self.call = nil
    }
    
    func callDidFail(with error: Swift.Error) {
        print("Got error while joining/leaving call: \(error).")
        
        self.eventSubject.send(.error(error))
        self.call = nil
    }
    
    public func callClient(_ callClient: CallClient, participantUpdated participant: Participant) {
        let isPlayable = participant.media?.microphone.state == Daily.MediaState.playable
        let isVapiSpeaker = participant.info.username == "Vapi Speaker"
        let shouldSendAppMessage = isPlayable && isVapiSpeaker
        
        guard shouldSendAppMessage else {
            return
        }
        
        do {
            let message: [String: Any] = ["message": "playable"]
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
            
            Task {
                try await call?.sendAppMessage(json: jsonData, to: .all)
            }
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }
    
    public func callClient(_ callClient: CallClient, callStateUpdated state: CallState) {
        switch (state) {
        case CallState.left:
            self.callDidLeave()
            break
        case CallState.joined:
            self.callDidJoin()
            break
        default:
            break
        }
    }
    
    public func callClient(_ callClient: Daily.CallClient, appMessageAsJson jsonData: Data, from participantID: Daily.ParticipantID) {
        do {
            let (dataToUse, payloadString) = normalizedAppMessageData(jsonData)

            // Detect listening message (plain string, not JSON object)
            if payloadString == "listening" {
                eventSubject.send(.callDidStart)
                return
            }

            let decoder = JSONDecoder()
            let appMessage: AppMessage
            do {
                appMessage = try decoder.decode(AppMessage.self, from: dataToUse)
            } catch {
                throw error
            }

            // Parse the JSON data again, this time using the specific type
            let event: Event
            switch appMessage.type {
            case .functionCall:
                // LEGACY: Direct function-call messages (kept for backward compatibility)
                // NOTE: Current Vapi versions send tool calls via dedicated tool-calls messages.
                // This handler remains for older Vapi versions or edge cases
                let functionCallMessage = try decoder.decode(FunctionCallMessage.self, from: dataToUse)
                event = Event.functionCall(functionCallMessage.functionCall)
            case .modelOutput:
                // Parse regular model output (text responses)
                // NOTE: Tool calls are handled via .toolCalls message type, not here
                do {
                    let modelOutput = try decoder.decode(ModelOutput.self, from: dataToUse)
                    event = Event.modelOutput(modelOutput)
                } catch {
                    // Silently skip if parsing fails
                    return
                }
            case .toolCalls:
                // Parse tool calls from dedicated tool-calls messages; emit each function-type call
                do {
                    let toolCallsMessage = try decoder.decode(ToolCallsMessage.self, from: dataToUse)
                    let functionCalls = toolCallsMessage.toolCalls.filter { $0.type == "function" }
                    guard !functionCalls.isEmpty else { return }
                    for toolCallItem in functionCalls {
                        let toolCall = try toolCallItem.toToolCall()
                        eventSubject.send(Event.toolCall(toolCall))
                    }
                    return
                } catch {
                    return
                }
            case .hang:
                event = Event.hang
            case .transcript:
                let transcript = try decoder.decode(Transcript.self, from: dataToUse)
                event = Event.transcript(transcript)
            case .speechUpdate:
                let speechUpdate = try decoder.decode(SpeechUpdate.self, from: dataToUse)
                event = Event.speechUpdate(speechUpdate)
            case .metadata:
                let metadata = try decoder.decode(Metadata.self, from: dataToUse)
                event = Event.metadata(metadata)
            case .conversationUpdate:
                let conv = try decoder.decode(ConversationUpdate.self, from: dataToUse)
                event = Event.conversationUpdate(conv)
            case .statusUpdate:
                let statusUpdate = try decoder.decode(StatusUpdate.self, from: dataToUse)
                event = Event.statusUpdate(statusUpdate)
            case .userInterrupted:
                let userInterrupted = UserInterrupted()
                event = Event.userInterrupted(userInterrupted)
            case .voiceInput:
                let voiceInput = try decoder.decode(VoiceInput.self, from: dataToUse)
                event = Event.voiceInput(voiceInput)
            }
            eventSubject.send(event)
        } catch {
            // Parsing failed; event not sent
        }
    }
}
