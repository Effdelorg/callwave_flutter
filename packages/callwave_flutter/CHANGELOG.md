# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking for custom platform implementations

- Custom `CallwaveFlutterPlatform` implementations must update `markMissed` to
  accept optional `extra`. Override `confirmAcceptedCall` only if using
  [IncomingAcceptStrategy.deferOpenUntilConfirmed]; it has a default no-op.
  The method channel implementation already includes these changes.

## [0.2.1] - 2026-03-06

### Fixed

- `started` event no longer regresses connected or reconnecting outgoing sessions
  to connecting state when cold-start routing (e.g. user taps ongoing call
  notification)

### Changed

- Clarified pubspec description for pub.dev

## [0.2.0] - 2026-03-06

### Added

- Conference session models: `CallParticipant` and `ConferenceState`
- `CallSession.updateConferenceState(...)` and `participantCount` for in-app
  conference orchestration
- Built-in conference `CallScreen` mode when participant count is greater than 1
- `CallwaveScope` conference customization hooks:
  `conferenceScreenBuilder`, `participantTileBuilder`, and
  `conferenceControlsBuilder`
- `CallwaveThemeData` for built-in conference styling while preserving current
  Callwave defaults
- `CallDataExtraKeys.androidMissedCallNotificationText` for customizable Android
  missed call notification body text
- `CallEventExtraKeys` with `launchAction` and `launchActionOpenOngoing` for
  platform launch actions (e.g. Android ongoing call notification tap)

### Changed

- Conference layout: primary and local panels now in left column; rail on right.
  Primary panel title simplified to "Current Speaker"
- Conference mode uses the current Callwave style and keeps controls as a plain
  bottom row with no rounded dock container
- Default conference controls are now call-type aware:
  video calls show `Mic`, `Speaker`, `Cam`, `End`;
  audio calls show `Mic`, `Speaker`, `End`
- One-to-one call UI remains unchanged and is still used for
  `participantCount <= 1`
- Refactored call actions layout and enhanced test coverage for video call actions
- Enhanced documentation and example app for missed call notifications

## [0.1.1] - 2026-03-05

### Changed

- Extended pubspec description for pub.dev
- Example app moved to `packages/callwave_flutter/example` for pub.dev recognition
- Example imports refactored to relative paths for IDE compatibility
- Listener function declaration in `callwave_flutter_impl.dart` clarified
- Deduplication logic in `call_session.dart` simplified with map literal
- Action button size made constant in `call_action_button.dart`
- Conference state instantiation in tests updated to use const constructor
- README enhanced with "Why callwave_flutter?" and platform status details

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
