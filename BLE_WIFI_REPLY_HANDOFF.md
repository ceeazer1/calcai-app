# BLE Wi-Fi reply investigation — October 17, 2026

## Version scope

Source-transfer update: the owner requested the latest code on the Mac.
`codex/ios-source-sync-20261017` contains this client patch and its tests.
The local/uncommitted statements below record the earlier investigation
checkpoint; a source transfer does not update the installed phone app.

Installed build 1100 (`a313ff8`) and uploaded build 1101 (`ce3d21b`) both
contain the original scan/list handling. **1101 does not contain the local
fixes described here.** No additional commit, upload, installation, firmware
edit, flash, pairing change or physical phone/device operation was performed.

The ESP32 Firmware investigation compared the preserved 1.4.0 tester source
with the exact 1100 client source. `bleEnqueue()` writes temporary `[]` while
work waits in the firmware queue. `bleDoListSaved()` also uses an array for its
completed result. A list row contains `ssid`, `slot` (1–3), and `iphoneHotspot`;
a scan row contains `ssid`, `rssi`, and `secured`. Lists contain no passwords.
Neither legacy response includes a request identity or completion marker.

1100/1101 accept any array as a completed saved list and persist it, including
the temporary `[]`. Wi-Fi scanning also bypasses the client's serialized
command queue, allowing another request to replace the shared characteristic.
These are source-confirmed risks; they do not prove which one caused the
particular physical-session symptom.

## Authentication follow-up

The firmware coordinator also found two concrete risks in 1100's Wi-Fi editor:
the authentication guard was cleared before `setWifiUiMode(true)` and
`_stopAutoConnecting`, and the nonce/cloud-proof/hello chain was not pinned to
its starting connection. Current local source contained the same risks.

The local fix holds an attempt identity through the entire handshake, including
the saved-list refresh within `proveOwnership` and the Wi-Fi-mode acknowledgement.
Generation, peripheral identity, account session and screen lifetime are checked
after each async boundary. A newer connection may start a fresh attempt while an
old cloud request finishes. Old `finally`/failure paths cannot clear that newer
guard, send a stale proof to its peripheral or disconnect it. Skip/retry on the
same link and hiding the screen invalidate the old attempt as well.

`BleService.proveOwnership` checks generation after hello and after the saved
list. Wi-Fi teardown and portal-close completion stay on their original
generation. Native disconnect cleanup captures its original handle/generation
and cannot erase a newer connection when the old native future completes.
No reconnect/scan/fallback/cloud timeout was increased; ownership proof remains
mandatory. No general reconnect or firmware protocol redesign is included.

Validation: **227 tests passed** across the full Flutter suite; analysis with
fatal infos found no issues, all 14 preflight checks and diff whitespace checks
passed. The 13 new cases cover repeated ready notifications, replacement
generations/devices, delayed nonce/cloud/hello/mode/list replies, logout,
skip/retry, current rejection, old teardown and delayed native disconnect.
`test/wifi_auth_race_test.dart` exercises the widget orchestration and real
disconnect cleanup with fake native handles; the two new ownership boundary
cases in `test/ble_wifi_reply_test.dart` exercise the real serialized command
path. Full-suite output is saved in the iOS chat workspace as
`wifi-auth-regression.log`. Initial fixture compilation and lint issues were
corrected before the passing results.

This is a local source fix only. The physical disconnect's cause remains
unproven, and build 1100/1101 still lack these changes. No upload, install,
hardware operation, backend mutation or firmware modification occurred.

## Local client changes

- Scan and list exchanges now use the same queue as other command-characteristic
  operations. Each captures the connection generation before being queued;
  disconnected/old-session work cannot write or publish a late result.
- A saved list must be nonempty and every row must match the saved-list shape
  before either cached SSIDs or hotspot flags are replaced and persisted.
  Temporary empty arrays, scan-shaped rows, malformed data, error objects and
  transport failures preserve the previous list and expose a retryable error.
- Scans accept scan-shaped rows, keep valid legacy CSV compatibility, report
  firmware failures and treat repeated `[]` as unconfirmed rather than a
  successful empty scan. Polling delay is never treated as proof of completion.
- Leaving Wi-Fi mode cancels pending scan polling so that the serialized
  normal-mode command can proceed. The cancelled reader ignores late replies;
  an uncorrelated same-connection reply seen by a later request remains a
  protocol limitation, as described below.
- Hotspot updates cannot claim success solely because the old cache already
  matched the requested value after a failed refresh.
- The Wi-Fi editor displays the refresh failure and Retry, alongside cached
  networks when available. Initial setup displays scan failures rather than
  an unsupported claim that no networks exist.

## Remaining protocol limitation and proposal

Validation of the local client patch: **67 targeted Flutter tests passed**,
including the 14 new transport/reply regressions and the new retry UI case,
plus existing Wi-Fi management, duplicate scans, portal status, V2 pairing,
device verification and both AI-sharing setup paths. Analysis with fatal infos
found no issues; all 14 release source/asset checks and `git diff --check`
passed. BLE replies in these tests are fixtures, not hardware observations.

An initial test invocation named nonexistent `device_verification_test.dart`;
that invocation failed to load that path. The corrected run used the existing
`device_verify_test.dart` and passed all 67 tests. No failure was suppressed.

Legacy `[]` cannot distinguish queued work from a completed empty list/scan.
The local client therefore cannot authoritatively clear a cached saved list
from an empty legacy list reply. Repeating reads or waiting longer does not
resolve this ambiguity. A late reply from another request of the same shape
also cannot be correlated conclusively. These limits require firmware support.

### Firmware follow-up assessment

The firmware owner's follow-up agrees with this mitigation's conservative
handling, but neither client serialization nor a new placeholder can correlate
an old final reply after a timeout/cancel followed by another request. That
requires a versioned request ID. The local 67-test suite verifies client-side
preservation/ordering; it is not evidence of end-to-end V2 protocol correctness.

**Do not publish a global pending/busy JSON object to legacy readers.** Build
1100/1101 scan handling can stop on its raw byte length and then parse no rows;
their generic command reader can accept an uncorrelated object. The old saved
list reader ignores objects. A zero-length characteristic while work is pending
is the smaller compatible interim proposal: the old readers keep waiting.
It does not fix overlapping finals or provide a request identity.

The local mitigation also keeps waiting on zero-length reads. It still cannot
infer whether a later legacy `[]` is authoritative, because it has no negotiated
guarantee about the firmware's placeholder behavior. In particular, merely
deploying a zero-length placeholder would not make this client clear a cached
list from `[]`. That conservative behavior is intentional.

### Concrete V2 proposal (documentation only)

Use the firmware owner's proposed names below. They supersede the earlier
generic envelope terminology in this handoff and are **not implemented,
negotiated, built or deployed by the local patch**.

1. Advertise `networkReplyVersion: 2` in the existing capability response only
   once the versioned path is implemented. A client opts in per request:

   ```json
   {"cmd":"list","replyVersion":2,"rid":"<fresh bounded request ID>"}
   ```

   `cmd` is `list` or `scan`. The final ID grammar/length must be agreed by both
   owners; a fresh 32-character hexadecimal nonce fits the existing app nonce
   generator. Enforce the agreed bound rather than accepting arbitrary strings.

2. A completed result echoes both command and request ID. A matching completed
   empty list is authoritative:

   ```json
   {"cmd":"list","rid":"<same ID>","state":"done","networks":[]}
   ```

   Terminal errors use the same correlation, for example `state:"error"` and
   an agreed `error` code. Admission errors (busy/unauthorized/bad request) need
   explicit handling too; they must not silently become successful emptiness.
   Malformed requests whose ID cannot be validated fail without accepting a
   completion or weakening ownership checks.

3. Carry command, negotiated version, request ID and connection generation in
   the queued firmware work. Publish only for the generation that accepted the
   request. Capture the same identity on the client before queuing; ignore
   wrong-command, wrong-ID, old-session and nonterminal replies. Do not reuse
   an ID for a new logical scan/list or fall back to raw arrays mid-request.

4. Retain the existing raw-array final format for legacy requests. Never switch
   all commands to an object envelope: pairing/auth/UI-mode readers have their
   own contracts. A zero-length pending value remains compatible; any future
   pending envelope must be negotiated and correlated for V2 requests only.

5. Enforce the **500-byte UTF-8 budget for the entire serialized envelope**,
   including ID, command and framing. Shorten scan results by complete rows
   only. Saved lists must be complete or return a correlated size error; never
   silently present a truncated saved list as authoritative. Never expose
   passwords, truncate JSON or change secure release artifacts.

Required coordinated source/fixture tests: delayed pending-to-empty completion;
two same-command requests with reversed finals; scan/list overlap; timeout and
cancellation followed by a new ID; reconnect with reused peripheral handle;
correlated busy/auth/storage failures; malformed/oversized replies; multibyte
SSIDs at the whole-envelope limit; legacy 1100/1101 behavior; and V2 client
fallback on an older capability response. A separate approved native test and
release are needed after both implementations exist.

## Permission-test expectations for 1100 and 1101

Neither 1101 nor this local Wi-Fi reply patch changes the permission guard.
`WifiScreen._attemptAutoConnect()` first reuses a connection already marked
ready (then authenticates it). Otherwise it calls `requestPermissions()` and
`isBluetoothOn()`. `requestPermissions()` treats all non-on adapter states alike
and waits up to 10 seconds for `on`; it does not distinguish iOS permission
denial from radio-off. Failure leads to the generic Bluetooth-disconnected UI.

For an available adapter, remembered-device reconnect gets one 4-second connect
attempt. If that fails, the scan path has a 12-second UI timer and a 10-second
BLE discovery scan. These are separate stages, not a single total deadline;
initial adapter reads/service discovery can add time. An already-ready cached
connection skips the initial permission guard. A first-seconds spinner alone
does not establish a failure; actual native authorization state and eventual
disconnection/error transitions must be observed by the physical test owner.
