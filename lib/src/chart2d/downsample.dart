/// Largest-Triangle-Three-Buckets downsampling (Steinarsson, 2013).
///
/// Picks [threshold] of the [count] points `(xs[i], ys[i])` (sorted by x)
/// that best preserve the line's visual shape: the first and last points
/// are always kept, and from each bucket in between it keeps the point
/// forming the largest triangle with its neighbours — so peaks and dips
/// survive, unlike naive every-nth sampling.
///
/// Returns indices into the input, in ascending order. If [count] is
/// already ≤ [threshold] (or [threshold] < 3), returns every index.
List<int> lttbIndices(int count, double Function(int i) xs, double Function(int i) ys, int threshold) {
  if (threshold >= count || threshold < 3) return List<int>.generate(count, (i) => i);

  final result = <int>[0];
  final bucketSize = (count - 2) / (threshold - 2);
  int a = 0; // previously selected point

  for (int b = 0; b < threshold - 2; b++) {
    // Average of the next bucket — the third triangle corner.
    final nextStart = ((b + 1) * bucketSize).floor() + 1;
    final nextEnd = (((b + 2) * bucketSize).floor() + 1).clamp(0, count);
    double avgX = 0, avgY = 0;
    final nextLen = nextEnd - nextStart;
    for (int i = nextStart; i < nextEnd; i++) {
      avgX += xs(i);
      avgY += ys(i);
    }
    if (nextLen > 0) {
      avgX /= nextLen;
      avgY /= nextLen;
    } else {
      avgX = xs(count - 1);
      avgY = ys(count - 1);
    }

    // The point in this bucket with the largest triangle area.
    final start = (b * bucketSize).floor() + 1;
    final end = ((b + 1) * bucketSize).floor() + 1;
    final ax = xs(a), ay = ys(a);
    double maxArea = -1;
    int chosen = start;
    for (int i = start; i < end; i++) {
      final area = ((ax - avgX) * (ys(i) - ay) - (ax - xs(i)) * (avgY - ay)).abs();
      if (area > maxArea) {
        maxArea = area;
        chosen = i;
      }
    }
    result.add(chosen);
    a = chosen;
  }

  result.add(count - 1);
  return result;
}
