enum CallPhase { idle, ringing, connecting, active, ended, failed }

class CallState {
  final CallPhase phase;
  final String callId;
  final String otherUid;
  final String otherName;
  final bool isCaller;
  final bool muted;
  final int seconds;
  final String? error;

  const CallState({
    required this.phase,
    required this.callId,
    required this.otherUid,
    required this.otherName,
    required this.isCaller,
    required this.muted,
    required this.seconds,
    this.error,
  });

  CallState copyWith({
    CallPhase? phase,
    String? callId,
    String? otherUid,
    String? otherName,
    bool? isCaller,
    bool? muted,
    int? seconds,
    String? error,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      otherUid: otherUid ?? this.otherUid,
      otherName: otherName ?? this.otherName,
      isCaller: isCaller ?? this.isCaller,
      muted: muted ?? this.muted,
      seconds: seconds ?? this.seconds,
      error: error ?? this.error,
    );
  }

  static CallState idle() => const CallState(
    phase: CallPhase.idle,
    callId: '',
    otherUid: '',
    otherName: '',
    isCaller: false,
    muted: false,
    seconds: 0,
  );
}
