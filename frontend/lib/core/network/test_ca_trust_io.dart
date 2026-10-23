import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// Base64 PEM of a private TEST certificate authority, supplied only for local
/// rehearsal builds: `--dart-define=EMS_TEST_CA_PEM_B64=...`.
const String _testCaPemB64 = String.fromEnvironment('EMS_TEST_CA_PEM_B64');

/// Physical-device testing against the local HTTPS rehearsal stack.
///
/// When a test CA is supplied in a NON-release build, the client trusts ONLY that
/// CA (not even the public roots). Certificate chain and hostname verification stay
/// fully on — there is no accept-all callback. Release builds ignore the define
/// entirely, so this can never weaken production TLS.
HttpClientAdapter? testCaAdapter() {
  if (kReleaseMode || kIsWeb || _testCaPemB64.isEmpty) return null;
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(base64Decode(_testCaPemB64));
  return IOHttpClientAdapter(createHttpClient: () => HttpClient(context: context));
}
