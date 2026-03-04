# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-03-04

### Added

- Initial release of callwave_flutter
- `CallwaveFlutter` singleton with `showIncomingCall`, `showOutgoingCall`, `endCall`, `markMissed`, and `Stream<CallEvent> events`
- `CallwaveEngine` and `CallSession` for session-first orchestration
- `CallScreen` widget for full-screen call UI (incoming/outgoing, accept/decline, mute/speaker/end)
- `CallwaveScope` and `CallStartupRouteDecision` for cold-start routing
- Android implementation: full-screen call intents, notifications, timeout scheduling (`AlarmManager`)
- iOS implementation: CallKit integration
- Event buffering for cold-start delivery (max 50 events, 10-minute TTL)
- `PostCallBehavior` for background-on-ended (Android)
- `CallDataExtraKeys` constants for WebRTC backends (roomId, meetingId, token, etc.)
