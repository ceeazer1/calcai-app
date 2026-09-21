import 'dart:async';
import 'package:flutter/foundation.dart';

/// Parsed v2 account allowance. A missing percentage is never a balance.
class AccountUsage {
  AccountUsage(this.json) {
    if (json['usageVersion'] != 2 ||
        json['scope'] != 'account' ||
        json['allowance'] is! Map) {
      throw const FormatException('Unsupported usage response');
    }
  }
  final Map<String, dynamic> json;
  Map get allowance => json['allowance'] as Map;
  bool get unlimited => allowance['unlimited'] == true;
  bool get syncing => json['status'] == 'syncing';
  bool get exhausted => allowance['exhausted'] == true;
  String get plan => json['plan']?.toString() ?? '';
  Map? get _welcome =>
      json['welcomeAllowance'] is Map ? json['welcomeAllowance'] as Map : null;
  bool get welcomeActive => _welcome?['active'] == true;
  DateTime? get welcomeExpiresAt =>
      DateTime.tryParse(_welcome?['expiresAt']?.toString() ?? '')?.toUtc();
  double? get remainingPercent {
    if (syncing || unlimited) return null;
    final value = allowance['remainingPercent'];
    if (value is! num || !value.isFinite || value < 0 || value > 100) {
      return null;
    }
    return value.toDouble();
  }

  DateTime? get serverTime =>
      DateTime.tryParse(json['serverTime']?.toString() ?? '')?.toUtc();
  DateTime? get resetsAt => DateTime.tryParse(
    (json['period'] as Map?)?['resetsAt']?.toString() ?? '',
  )?.toUtc();
  Set<String> get personalProviders => {
    for (final model in (json['models'] as List? ?? []))
      if (model is Map && model['billingSource'] == 'user')
        model['provider'].toString(),
  };
}

enum UsageFailure { offline, unavailable, session, forbidden }

/// Account-only state and scheduling, independent of paired hardware.
/// Only status GETs are retried; this class never submits an AI solve.
class UsageTracker extends ChangeNotifier {
  UsageTracker({required this.fetch, this.elapsed});
  final Duration Function()? elapsed;
  Duration _anchorElapsed = Duration.zero;
  final Future<Map<String, dynamic>> Function(String) fetch;
  AccountUsage? data;
  UsageFailure? failure;
  bool loading = false;
  bool forcedSyncing = false;
  Duration? _retryDeadline;
  bool _limitReached = false;
  DateTime? limitReset;
  String? _token;
  int _generation = 0;
  bool _visible = false;
  bool _disposed = false;
  Timer? _timer;
  DateTime? _serverAnchor;
  final Stopwatch _elapsed = Stopwatch()..start();
  String? _resetRequested;
  Future<void>? _inflight;

  Duration get _now => elapsed?.call() ?? _elapsed.elapsed;
  DateTime? get serverNow => _serverAnchor?.add(_now - _anchorElapsed);
  DateTime? get resetsAt => limitReset ?? data?.resetsAt;
  bool get expired =>
      serverNow != null &&
      ((resetsAt != null && !serverNow!.isBefore(resetsAt!)) ||
          (data?.welcomeActive == true &&
              data?.welcomeExpiresAt != null &&
              !serverNow!.isBefore(data!.welcomeExpiresAt!)));
  bool get syncing => forcedSyncing || data?.syncing == true;
  bool get exhausted =>
      _limitReached ||
      (data?.exhausted == true && data?.remainingPercent != null);
  bool get stale => data != null && failure != null;
  Duration? get resetIn => serverNow == null || resetsAt == null
      ? null
      : resetsAt!.difference(serverNow!);

  void bind(String? token) {
    if (_token == token) return;
    clear();
    _token = token;
  }

  void clear() {
    _generation++;
    _timer?.cancel();
    _inflight = null;
    _token = null;
    data = null;
    failure = null;
    loading = false;
    forcedSyncing = false;
    _limitReached = false;
    limitReset = null;
    _retryDeadline = null;
    _serverAnchor = null;
    _resetRequested = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    _schedule();
  }

  /// A status request started before a solve may not include its cost yet.
  Future<void> refreshAfterSolve() async {
    final generation = _generation;
    if (_inflight != null) await _inflight;
    if (!_disposed && generation == _generation) await refresh();
  }

  Future<void> refresh() {
    if (_disposed || _token == null) return Future.value();
    if (_inflight != null) return _inflight!;
    if (_retryDeadline != null && _now < _retryDeadline!) {
      _schedule();
      return Future.value();
    }
    final generation = _generation;
    final token = _token!;
    final completion = Completer<void>();
    _inflight = completion.future;
    loading = true;
    _notify();
    () async {
      try {
        final parsed = AccountUsage(await fetch(token));
        if (_disposed || generation != _generation) return;
        // The server time anchor advances monotonically, ignoring wall-clock skew.
        if (parsed.serverTime == null || parsed.resetsAt == null) {
          throw const FormatException('Missing usage period');
        }
        data = parsed;
        _serverAnchor = parsed.serverTime;
        _anchorElapsed = _now;
        failure = null;
        forcedSyncing = false;
        _limitReached = false;
        limitReset = null;
        _retryDeadline = null;
      } on UsageRequestException catch (e) {
        if (_disposed || generation != _generation) return;
        handleError(e, notify: false);
      } on FormatException {
        if (_disposed || generation != _generation) return;
        failure = UsageFailure.unavailable;
      } catch (_) {
        if (_disposed || generation != _generation) return;
        failure = UsageFailure.offline;
      } finally {
        if (!_disposed && generation == _generation) {
          loading = false;
          _inflight = null;
          _schedule();
          _notify();
        }
        completion.complete();
      }
    }();
    return completion.future;
  }

  void handleError(UsageRequestException e, {bool notify = true}) {
    if (e.status == 401 || e.status == 403) {
      data = null;
      forcedSyncing = false;
      _limitReached = false;
      limitReset = null;
      _retryDeadline = null;
      failure = e.status == 401 ? UsageFailure.session : UsageFailure.forbidden;
    } else if (e.status == 429 && e.code == 'usage_limit_reached') {
      _limitReached = true;
      limitReset = e.resetsAt;
      // Without a reset timestamp there is no safe synthetic period to show.
      forcedSyncing = false;
      _retryDeadline = null;
      failure = null;
    } else if (e.status == 503 && e.code == 'usage_syncing') {
      forcedSyncing = true;
      failure = null;
      _retryDeadline = _now + (e.retryAfter ?? const Duration(seconds: 15));
    } else {
      failure = UsageFailure.unavailable;
    }
    _schedule();
    if (notify) _notify();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed ||
        !_visible ||
        _token == null ||
        loading ||
        failure == UsageFailure.session ||
        failure == UsageFailure.forbidden) {
      return;
    }
    if (syncing) {
      final wait = _retryDeadline == null ? null : _retryDeadline! - _now;
      _timer = Timer(
        wait != null && wait > Duration.zero
            ? wait
            : const Duration(seconds: 15),
        refresh,
      );
    } else if (resetIn != null) {
      var refreshAt = resetsAt!;
      final welcomeEnd = data?.welcomeExpiresAt;
      if (data?.welcomeActive == true &&
          welcomeEnd != null &&
          welcomeEnd.isBefore(refreshAt)) {
        refreshAt = welcomeEnd;
      }
      final period = refreshAt.toIso8601String();
      if (_resetRequested == period) return;
      final wait = refreshAt.difference(serverNow!);
      _timer = Timer(wait > Duration.zero ? wait : Duration.zero, () {
        _resetRequested = period;
        refresh();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }
}

class UsageRequestException implements Exception {
  const UsageRequestException(
    this.status,
    this.code, {
    this.retryAfter,
    this.resetsAt,
  });
  final int status;
  final String code;
  final Duration? retryAfter;
  final DateTime? resetsAt;
}
