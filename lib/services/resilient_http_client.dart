// Keep native Foundation/FFI libraries out of browser builds.
export 'http_transport_web.dart'
    if (dart.library.io) 'http_transport_native.dart';
