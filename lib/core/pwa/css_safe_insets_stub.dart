import 'package:flutter/painting.dart';

/// No VM o navegador não tem `env(safe-area-inset-*)`.
EdgeInsets readCssSafeAreaInsets() => EdgeInsets.zero;
