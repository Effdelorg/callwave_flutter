# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-03-07

### Added

- `CallStartupActionDto` and `CallStartupActionType` for missed-call startup actions
- `takePendingStartupAction()` on `CallwaveFlutterPlatform` for one-shot actions
  captured before Flutter finished initializing
- `PayloadCodec.startupActionToMap` and `safeStartupActionFromMap` for wire encoding

## [0.1.1] - 2026-03-05

### Changed

- Extended pubspec description for pub.dev
- README enhanced with "Why callwave_flutter?" and platform status details

## [0.1.0] - 2025-03-04

### Added

- Initial release of callwave_flutter_platform_interface
- Abstract `CallwaveFlutterPlatform` extending `PlatformInterface`
- DTO models: `CallDataDto`, `CallEventDto`
- `PayloadCodec` for Dart map ↔ DTO conversion
- Enums with wire serialization: `CallEventType`, `CallType`, `PostCallBehavior`
