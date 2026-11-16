// Isolated native-component acceptance harness. Never imported by lib/main.dart.
// Build only for an iOS simulator with --dart-define=CALCAI_NATIVE_FIXTURE=true.
// No real account, device, server request, keychain read or AI inference.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:calcai_app/screens/photo_view_screen.dart';
import 'package:calcai_app/services/auth_service.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class _LocalAuth extends AuthService {
  _LocalAuth()
    : super(
        httpClient: MockClient(
          (_) async => throw StateError('No network in fixture'),
        ),
      );
  String? _localToken = 'synthetic-native-fixture';
  @override
  String? get token => _localToken;
  void endLocalSession() {
    _localToken = null;
    notifyListeners();
  }

  void resetLocalSession() {
    _localToken =
        'synthetic-native-fixture-${DateTime.now().microsecondsSinceEpoch}';
    notifyListeners();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      !const bool.fromEnvironment('CALCAI_NATIVE_FIXTURE') ||
      !Platform.isIOS ||
      !Platform.environment.containsKey('SIMULATOR_MODEL_IDENTIFIER')) {
    throw StateError(
      'Native photo fixture requires an explicitly enabled debug iOS simulator.',
    );
  }
  GoogleFonts.config.allowRuntimeFetching = false;
  final temporary = Directory(
    '${(await getTemporaryDirectory()).path}/native-photo-fixture',
  );
  await temporary.create(recursive: true);
  final marker = File('${temporary.path}/keep-fixture.txt');
  await marker.writeAsString('Unrelated file must survive export cleanup.');
  final auth = _LocalAuth();
  runApp(
    ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => Column(
          children: [
            const Material(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Text(
                    'NATIVE COMPONENT FIXTURE — SYNTHETIC IMAGE / NO ACCOUNT',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
            Expanded(child: child!),
            Material(
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: auth.endLocalSession,
                      child: const Text('End local session'),
                    ),
                    TextButton(
                      onPressed: auth.resetLocalSession,
                      child: const Text('Reset local session'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        home: _FixtureHome(temporary: temporary, marker: marker),
      ),
    ),
  );
}

class _FixtureHome extends StatefulWidget {
  const _FixtureHome({required this.temporary, required this.marker});
  final Directory temporary;
  final File marker;
  @override
  State<_FixtureHome> createState() => _FixtureHomeState();
}

class _FixtureHomeState extends State<_FixtureHome> {
  String _diagnostics =
      'Open the real photo component with a local synthetic PNG.';
  Future<void> _inspect() async {
    final entries = await widget.temporary.list(followLinks: false).toList();
    final own = entries
        .whereType<Directory>()
        .where(
          (entry) => entry.path.split('/').last.startsWith('calcai-photo-'),
        )
        .length;
    final markerPresent = await widget.marker.exists();
    if (mounted) {
      setState(
        () => _diagnostics =
            'Temporary photo directories: $own\nUnrelated fixture file retained: $markerPresent',
      );
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PhotoViewScreen(
          imageUrl:
              'https://ai.calcai.cc/ai/image/view/00000000000000000000000000000000',
          client: MockClient((request) async {
            if (request.method != 'GET' || request.url.host != 'ai.calcai.cc') {
              throw StateError('Unexpected fixture request');
            }
            return http.Response.bytes(
              _png,
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
          imageProvider: MemoryImage(_png),
          temporaryDirectoryProvider: () async => widget.temporary,
        ),
      ),
    );
    await _inspect();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Native photo acceptance')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The photo screen and Gal/Share plugins are production components. Image, session and download are isolated local fixtures. No backend is contacted.',
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _open,
            child: const Text('Open synthetic photo'),
          ),
          TextButton(
            onPressed: _inspect,
            child: const Text('Inspect fixture cleanup'),
          ),
          SelectableText(_diagnostics),
        ],
      ),
    ),
  );
}
