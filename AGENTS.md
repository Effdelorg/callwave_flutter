# callwave_flutter — Agent Guide

Federated Flutter plugin for WhatsApp-style VoIP call UX (incoming call UI, accept/decline/timeout, CallKit/Android full-screen intents). No WebRTC/SIP/audio routing.

Always check for race conditions in the code and fix them. 

## Workspace Structure

| Package | Role |
|---------|------|
| `packages/callwave_flutter` | Public API for app developers |
| `packages/callwave_flutter_platform_interface` | Shared contracts, DTOs, codec |
| `packages/callwave_flutter_method_channel` | MethodChannel + Android (Kotlin) / iOS (Swift) |
| `example` | Demo app for manual testing |

## Conventions

- **Clean architecture**: Platform interface defines contracts; method channel implements them.
- **Workspace**: Use `dart pub get` at root; `dart run melos run analyze` / `dart run melos run test` for cross-package tasks.
- Keep changes minimal. Follow existing patterns in the codebase.

## What Not to Add

- WebRTC, SIP signaling, audio routing/recording (out of scope).
