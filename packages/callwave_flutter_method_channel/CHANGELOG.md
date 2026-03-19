# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.6] - 2026-03-19

### Fixed

- iOS: `CXCallController` completion errors for outgoing start and end no longer
  emit false success; outgoing failure rolls back state and emits `ended` with
  `outcomeReason`; end failure emits `ended` with `outcomeReason` without clearing
  native UUID mapping so `endCall` can be retried
- iOS: `reportNewIncomingCall` failure now emits `declined` with `outcomeReason`
  after rollback (previously silent to Flutter)
- iOS: background accept validation and decline reporting use an 8s timeout
  matching Android (`IOSBackgroundValidator`), with idempotent completion if the
  channel returns after timeout

## [0.1.5] - 2026-03-10

### Added

- `canScheduleExactAlarms()` and `requestExactAlarmPermission()` for Android 12+
  exact alarm scheduling (call timeout reliability)
- Android: `DeclineReportBridgeActivity` for headless decline reporting when app
  is terminated
- Android: `IncomingRingtoneController` and `IncomingCallStore` for ringtone
  behavior and incoming call state
- Android: Exact alarm scheduling for call timeout (replaces inexact alarms)
- iOS: `BackgroundValidatorRegistrationStore` and `IncomingCallStore` for
  background decline handling

### Changed

- Android: Notification channel ID bumped to v3 for incoming calls
- Android: Decline from full-screen UI routes through bridge when background
  validator is registered

## [0.1.4] - 2026-03-07

### Fixed

- Tightened `callwave_flutter_platform_interface` constraint to `^0.1.2` for
  pub.dev compatibility scoring

## [0.1.3] - 2026-03-07

### Added

- Missed-call notifications on iOS with "Call Back" action and tap-to-open
- `takePendingStartupAction` method for cold-start handoff of missed-call actions
- Android missed-call notification content intent (tap body opens app with
  `ACTION_OPEN_MISSED_CALL`)
- Headless decline reporting for terminated incoming calls on Android and iOS,
  with missed-call fallback when the background Dart callback fails

### Changed

- **Android**: `CallNotificationManager.showMissedCall` now requires `contentIntent`
  in addition to `callbackIntent`
- **iOS**: `requestNotificationPermission` now requests permission via
  `UNUserNotificationCenter` instead of always returning `true`

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
