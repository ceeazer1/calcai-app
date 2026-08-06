import 'package:flutter_test/flutter_test.dart';
import 'package:calcai_app/screens/dashboard_screen.dart';
import 'package:calcai_app/services/ble_service.dart';
import 'package:calcai_app/services/cloud_service.dart';
import 'package:calcai_app/models/calc_note.dart';

void main() {
  test('seeded preview service builds without throwing', () async {
    final c = PreviewCloudService(seeded: true);
    // notes only populate on fetch, same as the real service.
    await c.getNotes('t', 'm');
    expect(c.history.length, 5);
    expect(c.cheapUsage, 12);
    expect(c.currentModel, 'gpt-5.6-sol');
    final notes = CalcNote.parseStored(c.notes ?? '');
    expect(notes.length, 3);
  });

  test('preview BLE service seeds a saved network for the home card', () async {
    final b = PreviewBleService();
    expect(b.savedNetworks, contains('Home WiFi'));
    expect(b.connectedSsid, 'Home WiFi');
    // Startup calls this; it must not wipe the seed.
    await b.loadPersistedNetworks('ca1ca1000001');
    expect(b.savedNetworks, isNotEmpty);
  });

  test('every model in the picker is priced consistently', () {
    // gpt-5.6-sol is the flagship, so it must not read as free.
    expect(isFreeModel('gpt-5.6-sol'), isFalse);
    expect(isFreeModel('gpt-5.6-luna'), isTrue);
  });

  test('unseeded preview service is empty', () {
    final c = PreviewCloudService();
    expect(c.history, isEmpty);
    expect(c.cheapUsage, 0);
  });
}
