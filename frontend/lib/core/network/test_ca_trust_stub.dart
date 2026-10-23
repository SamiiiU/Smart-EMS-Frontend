import 'package:dio/dio.dart';

/// Web and unsupported platforms: never a custom trust store.
HttpClientAdapter? testCaAdapter() => null;
