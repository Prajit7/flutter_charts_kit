// A minimal animated-GIF encoder for the README media (tool only — not part
// of the package). Frames are RGBA; one global palette (≤ 256 colours) is
// built from all frames, each frame is LZW-compressed, and the GIF loops.
import 'dart:typed_data';

class GifEncoder {
  final int width;
  final int height;

  /// Delay per frame, in hundredths of a second.
  final int delay;
  final List<Uint8List> _frames = [];

  GifEncoder(this.width, this.height, {this.delay = 6});

  void addFrame(Uint8List rgba) {
    assert(rgba.length == width * height * 4);
    _frames.add(rgba);
  }

  /// 15-bit key (5 bits per channel) used for the histogram and lookup cache.
  static int _key(int r, int g, int b) => (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3);

  Uint8List encode() {
    // Palette: the 256 most common 15-bit colours across all frames —
    // charts are mostly flat fills, so this captures them well; antialiased
    // edges map to the nearest entry.
    final counts = <int, int>{};
    final sums = <int, List<int>>{};
    for (final f in _frames) {
      for (int i = 0; i < f.length; i += 4 * 3) {
        final k = _key(f[i], f[i + 1], f[i + 2]);
        counts[k] = (counts[k] ?? 0) + 1;
        final s = sums[k] ??= [0, 0, 0];
        s[0] += f[i];
        s[1] += f[i + 1];
        s[2] += f[i + 2];
      }
    }
    final top = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final chosen = top.take(256).toList();
    final palette = Uint8List(256 * 3);
    for (int i = 0; i < chosen.length; i++) {
      final s = sums[chosen[i]]!, n = counts[chosen[i]]!;
      palette[i * 3] = s[0] ~/ n;
      palette[i * 3 + 1] = s[1] ~/ n;
      palette[i * 3 + 2] = s[2] ~/ n;
    }
    final cache = <int, int>{};
    int nearest(int r, int g, int b) {
      final k = _key(r, g, b);
      return cache[k] ??= () {
        var best = 0, bestD = 1 << 30;
        for (int i = 0; i < chosen.length; i++) {
          final dr = palette[i * 3] - r, dg = palette[i * 3 + 1] - g, db = palette[i * 3 + 2] - b;
          final d = dr * dr * 2 + dg * dg * 4 + db * db * 3;
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        return best;
      }();
    }

    final out = BytesBuilder();
    void u16(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF]);
    out.add('GIF89a'.codeUnits);
    u16(width);
    u16(height);
    out.add([0xF7, 0, 0]); // global colour table, 8 bits, 256 entries
    out.add(palette);
    // Loop forever (NETSCAPE2.0).
    out.add([0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0]);
    Uint8List? prev;
    for (final f in _frames) {
      // Only the rectangle that changed since the previous frame is stored;
      // the rest of the previous frame stays on screen (disposal 1).
      var x0 = 0, y0 = 0, x1 = width - 1, y1 = height - 1;
      if (prev != null) {
        x0 = width;
        y0 = height;
        x1 = -1;
        y1 = -1;
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final i = (y * width + x) * 4;
            if (f[i] != prev[i] || f[i + 1] != prev[i + 1] || f[i + 2] != prev[i + 2]) {
              if (x < x0) x0 = x;
              if (x > x1) x1 = x;
              if (y < y0) y0 = y;
              if (y > y1) y1 = y;
            }
          }
        }
        if (x1 < 0) {
          // Identical frame: a 1×1 patch keeps the timing.
          x0 = x1 = 0;
          y0 = y1 = 0;
        }
      }
      final w = x1 - x0 + 1, h = y1 - y0 + 1;
      final indices = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final i = ((y0 + y) * width + x0 + x) * 4;
          indices[y * w + x] = nearest(f[i], f[i + 1], f[i + 2]);
        }
      }
      out.add([0x21, 0xF9, 4, 0x04, delay & 0xFF, delay >> 8, 0, 0]); // graphic control, disposal 1
      out.add([0x2C]);
      u16(x0);
      u16(y0);
      u16(w);
      u16(h);
      out.add([0]);
      out.add([8]); // LZW minimum code size
      final data = _lzw(indices);
      for (int i = 0; i < data.length; i += 255) {
        final n = (data.length - i).clamp(0, 255);
        out.add([n]);
        out.add(data.sublist(i, i + n));
      }
      out.add([0]);
      prev = f;
    }
    out.add([0x3B]);
    return out.toBytes();
  }

  /// GIF-flavoured LZW with an 8-bit alphabet.
  static Uint8List _lzw(Uint8List pixels) {
    const clear = 256, end = 257;
    final out = BytesBuilder();
    var bitBuf = 0, bitCount = 0, codeSize = 9;
    void emit(int code) {
      bitBuf |= code << bitCount;
      bitCount += codeSize;
      while (bitCount >= 8) {
        out.addByte(bitBuf & 0xFF);
        bitBuf >>= 8;
        bitCount -= 8;
      }
    }

    var dict = <int, int>{};
    var next = 258;
    emit(clear);
    var prefix = pixels[0];
    for (int i = 1; i < pixels.length; i++) {
      final c = pixels[i];
      final key = prefix << 8 | c;
      final found = dict[key];
      if (found != null) {
        prefix = found;
        continue;
      }
      emit(prefix);
      if (next < 4096) {
        dict[key] = next++;
        if (next > (1 << codeSize) && codeSize < 12) codeSize++;
      } else {
        emit(clear);
        dict = {};
        next = 258;
        codeSize = 9;
      }
      prefix = c;
    }
    emit(prefix);
    emit(end);
    if (bitCount > 0) out.addByte(bitBuf & 0xFF);
    return out.toBytes();
  }
}
