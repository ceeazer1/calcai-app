/// Requires a complete, unambiguous discovery before any bench connection.
/// Name filtering is only a transport allowlist; normal identity/owner proof
/// remains mandatory after connecting.
class BenchTargetPolicy {
  BenchTargetPolicy({required this.targetName, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String targetName;
  final DateTime Function() _clock;
  final Set<String> _candidates = {};
  bool _scanning = false;
  String? _allowedId;
  DateTime? _completedAt;

  void beginScan() {
    invalidate();
    _scanning = true;
  }

  bool matchesName(String name) =>
      name.toUpperCase() == targetName.toUpperCase();

  void observe(String name, String id) {
    if (_scanning && matchesName(name) && id.isNotEmpty) {
      _candidates.add(id);
    }
  }

  void completeScan() {
    if (!_scanning) return;
    _scanning = false;
    if (_candidates.length == 1) {
      _allowedId = _candidates.single;
      _completedAt = _clock();
    }
  }

  String? get allowedId => _allowedId;
  bool get ambiguous => _candidates.length > 1;

  bool allows(String name, String id) =>
      !_scanning &&
      matchesName(name) &&
      id == _allowedId &&
      _completedAt != null &&
      _clock().difference(_completedAt!) >= Duration.zero &&
      _clock().difference(_completedAt!) <= const Duration(seconds: 60);

  void invalidate() {
    _scanning = false;
    _candidates.clear();
    _allowedId = null;
    _completedAt = null;
  }
}
