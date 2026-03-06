# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-03-06

### Added

- Customizable missed call notification body text via
  `androidMissedCallNotificationText` in call payload extra

### Changed

- Outgoing calls now show ongoing notification with open/end intents (replaces
  separate outgoing notification)
- Ongoing call notification shows "Call Ongoing" title and "CallerName (type)"
  body
- Improved event emission when user opens app from ongoing call notification
  (accept vs started)

## [0.1.1] - 2026-03-05

### Changed

- Extended pubspec description for pub.dev
- README enhanced with "Why callwave_flutter?" and platform status details

## [0.1.0] - 2025-03-04

### Added

- Initial release of callwave_flutter_method_channel
- `MethodChannelCallwaveFlutter` implementation of `CallwaveFlutterPlatform`
- MethodChannel and EventChannel bridge for call operations and events
- Android implementation: full-screen call intents, notifications, timeout scheduling (`AlarmManager`)
- iOS implementation: CallKit integration via `CXProvider` and `CXCallController`
- Event buffering for cold-start delivery (max 50 events, 10-minute TTL)
