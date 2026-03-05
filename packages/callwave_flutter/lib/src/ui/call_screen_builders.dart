import 'package:flutter/widgets.dart';

import '../engine/call_session.dart';
import '../models/call_participant.dart';

typedef ConferenceScreenBuilder = Widget Function(
  BuildContext context,
  CallSession session,
);

typedef ParticipantTileBuilder = Widget Function(
  BuildContext context,
  CallSession session,
  CallParticipant participant,
  bool isPrimary,
);

typedef ConferenceControlsBuilder = Widget Function(
  BuildContext context,
  CallSession session,
);
