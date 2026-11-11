import 'dart:math' as math;

/// A color in CIE L*a*b*.
final class Lab {
  /// Creates a Lab color.
  const Lab(this.l, this.a, this.b);

  /// Converts an sRGB `0xAARRGGBB` value (alpha ignored) to Lab, using the
  /// D65 white point.
  factory Lab.fromArgb(int argb) {
    double channel(int shift) {
      final c = ((argb >> shift) & 0xFF) / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = channel(16);
    final g = channel(8);
    final bl = channel(0);
    final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * bl) / 0.95047;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * bl;
    final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * bl) / 1.08883;

    double f(double t) => t > 216 / 24389
        ? math.pow(t, 1 / 3).toDouble()
        : (24389 / 27 * t + 16) / 116;

    final fx = f(x);
    final fy = f(y);
    final fz = f(z);
    return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  /// Lightness.
  final double l;

  /// Green-red axis.
  final double a;

  /// Blue-yellow axis.
  final double b;
}

/// The CIEDE2000 color difference between [x] and [y].
double ciede2000(Lab x, Lab y) {
  const kL = 1.0;
  const kC = 1.0;
  const kH = 1.0;
  final c1 = math.sqrt(x.a * x.a + x.b * x.b);
  final c2 = math.sqrt(y.a * y.a + y.b * y.b);
  final cBar = (c1 + c2) / 2;
  final cBar7 = math.pow(cBar, 7).toDouble();
  final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + math.pow(25, 7))));
  final a1 = (1 + g) * x.a;
  final a2 = (1 + g) * y.a;
  final cp1 = math.sqrt(a1 * a1 + x.b * x.b);
  final cp2 = math.sqrt(a2 * a2 + y.b * y.b);
  double hue(double b, double a) {
    if (b == 0 && a == 0) return 0;
    final h = math.atan2(b, a) * 180 / math.pi;
    return h >= 0 ? h : h + 360;
  }

  final hp1 = hue(x.b, a1);
  final hp2 = hue(y.b, a2);
  final dLp = y.l - x.l;
  final dCp = cp2 - cp1;
  double dhp;
  if (cp1 * cp2 == 0) {
    dhp = 0;
  } else if ((hp2 - hp1).abs() <= 180) {
    dhp = hp2 - hp1;
  } else if (hp2 - hp1 > 180) {
    dhp = hp2 - hp1 - 360;
  } else {
    dhp = hp2 - hp1 + 360;
  }
  final dHp = 2 * math.sqrt(cp1 * cp2) * math.sin(dhp * math.pi / 360);
  final lBarP = (x.l + y.l) / 2;
  final cBarP = (cp1 + cp2) / 2;
  double hBarP;
  if (cp1 * cp2 == 0) {
    hBarP = hp1 + hp2;
  } else if ((hp1 - hp2).abs() <= 180) {
    hBarP = (hp1 + hp2) / 2;
  } else if (hp1 + hp2 < 360) {
    hBarP = (hp1 + hp2 + 360) / 2;
  } else {
    hBarP = (hp1 + hp2 - 360) / 2;
  }
  double rad(double deg) => deg * math.pi / 180;
  final t =
      1 -
      0.17 * math.cos(rad(hBarP - 30)) +
      0.24 * math.cos(rad(2 * hBarP)) +
      0.32 * math.cos(rad(3 * hBarP + 6)) -
      0.20 * math.cos(rad(4 * hBarP - 63));
  final dTheta = 30 * math.exp(-math.pow((hBarP - 275) / 25, 2));
  final cBarP7 = math.pow(cBarP, 7).toDouble();
  final rC = 2 * math.sqrt(cBarP7 / (cBarP7 + math.pow(25, 7)));
  final lMinus50Sq = math.pow(lBarP - 50, 2);
  final sL = 1 + 0.015 * lMinus50Sq / math.sqrt(20 + lMinus50Sq);
  final sC = 1 + 0.045 * cBarP;
  final sH = 1 + 0.015 * cBarP * t;
  final rT = -math.sin(rad(2 * dTheta)) * rC;
  final lTerm = dLp / (kL * sL);
  final cTerm = dCp / (kC * sC);
  final hTerm = dHp / (kH * sH);
  return math.sqrt(
    lTerm * lTerm + cTerm * cTerm + hTerm * hTerm + rT * cTerm * hTerm,
  );
}
