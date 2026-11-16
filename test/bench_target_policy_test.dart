import 'package:calcai_app/services/bench_target_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late BenchTargetPolicy policy;
  setUp(() {
    now = DateTime.utc(2026, 11, 11);
    policy = BenchTargetPolicy(targetName: 'CALCAI-C62E', clock: () => now);
  });
  test(
    'fresh complete discovery gates exact-name and UUID before connection',
    () {
      policy.beginScan();
      policy.observe('CALCAI-C386', 'old');
      policy.observe('CALCAI-C62E', 'bench');
      expect(policy.allows('CALCAI-C62E', 'bench'), isFalse);
      policy.completeScan();
      expect(policy.allows('CALCAI-C62E', 'bench'), isTrue);
      expect(policy.allows('CALCAI-C386', 'bench'), isFalse);
      expect(policy.allows('CALCAI-C62E', 'other'), isFalse);
      now = now.add(const Duration(seconds: 61));
      expect(policy.allows('CALCAI-C62E', 'bench'), isFalse);
    },
  );
  test('accepts the ESP32 advertisement spelling for the LCD target', () {
    policy.beginScan();
    policy.observe('CalcAI-C386', 'old');
    policy.observe('CalcAI-C62E', 'bench');
    policy.completeScan();
    expect(policy.allowedId, 'bench');
    expect(policy.allows('CalcAI-C62E', 'bench'), isTrue);
    expect(policy.allows('CALCAI-C62E', 'bench'), isTrue);
    expect(policy.allows('CalcAI-C386', 'bench'), isFalse);
    expect(policy.allows('CalcAI-C62E', 'old'), isFalse);
  });
  test('multiple matching peripherals fail closed regardless of ordering', () {
    policy.beginScan();
    policy.observe('CALCAI-C62E', 'a');
    policy.observe('CALCAI-C62E', 'b');
    policy.completeScan();
    expect(policy.ambiguous, isTrue);
    expect(policy.allowedId, isNull);
    expect(policy.allows('CALCAI-C62E', 'a'), isFalse);
  });
  test('cancel and a new discovery revoke previous authorization', () {
    policy.beginScan();
    policy.observe('CALCAI-C62E', 'a');
    policy.completeScan();
    policy.beginScan();
    policy.completeScan();
    expect(policy.allowedId, isNull);
    policy.beginScan();
    policy.observe('CALCAI-C62E', 'a');
    policy.invalidate();
    policy.completeScan();
    expect(policy.allows('CALCAI-C62E', 'a'), isFalse);
  });
}
