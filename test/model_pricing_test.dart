import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/screens/dashboard_screen.dart';

void main() {
  test('free-tier list matches how the worker bills each model', () {
    // These mirror CHEAP_MODELS in edge-worker/src/worker.js. If they drift,
    // the app labels a model free that the backend charges as premium.
    expect(isFreeModel('gpt-5.6-luna'), isTrue);
    expect(isFreeModel('gemini-3.5-flash'), isTrue);
    expect(isFreeModel('claude-haiku-4-5'), isTrue);

    expect(isFreeModel('gpt-5.6-sol'), isFalse);
    expect(isFreeModel('claude-opus-5'), isFalse);
  });
}
