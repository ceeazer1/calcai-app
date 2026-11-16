import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ResponseTooLargeException implements Exception {
  const ResponseTooLargeException(this.limit);
  final int limit;

  @override
  String toString() => 'Response exceeds the permitted size';
}

/// Cancelling Cupertino's response stream waits for its native task to settle.
/// Always await that cancellation before a caller releases/closes the client.
Future<Uint8List> readBoundedResponse(
  http.StreamedResponse response, {
  int? maxResponseBytes,
  Future<void>? abortTrigger,
  void Function()? onLimitExceeded,
}) async {
  if (maxResponseBytes != null && maxResponseBytes < 0) {
    throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
  }
  if (maxResponseBytes != null &&
      (response.contentLength ?? 0) > maxResponseBytes) {
    onLimitExceeded?.call();
    // StreamIterator listens lazily. Subscribe explicitly here so cancel waits
    // for Cupertino's onCancel/native task completion even before any data.
    final subscription = response.stream.listen(
      null,
      onError: (Object _, StackTrace __) {},
    );
    await subscription.cancel();
    throw ResponseTooLargeException(maxResponseBytes);
  }
  final iterator = StreamIterator<List<int>>(response.stream);
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  var aborted = false;
  final cancellation = abortTrigger?.then<bool>((_) {
    aborted = true;
    return false;
  });
  try {
    while (await (cancellation == null
        ? iterator.moveNext()
        : Future.any([iterator.moveNext(), cancellation]))) {
      if (aborted) {
        throw http.RequestAbortedException(response.request?.url);
      }
      final chunk = iterator.current;
      if (maxResponseBytes != null &&
          chunk.length > maxResponseBytes - length) {
        onLimitExceeded?.call();
        throw ResponseTooLargeException(maxResponseBytes);
      }
      length += chunk.length;
      bytes.add(chunk);
    }
    if (aborted) {
      throw http.RequestAbortedException(response.request?.url);
    }
    return bytes.takeBytes();
  } finally {
    await iterator.cancel();
  }
}
