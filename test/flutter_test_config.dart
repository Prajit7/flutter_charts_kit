import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file. Swaps in a golden comparator that tolerates
/// a tiny fraction of differing pixels, so goldens generated on macOS still
/// pass on the Linux CI runner (anti-aliasing differs slightly between them).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = _TolerantGoldenComparator(comparator.basedir.resolve('golden_test.dart'));
  }
  await testMain();
}

class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(super.testFile);

  /// Max fraction of pixels allowed to differ (0.01 = 1%).
  static const double _tolerance = 0.01;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
