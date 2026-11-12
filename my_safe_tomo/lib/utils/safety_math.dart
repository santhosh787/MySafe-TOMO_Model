import 'dart:math' as math;

class SafetyMath {
  /// Magnitude in m/s². This is a coarse impact candidate, not proof of injury.
  static double accelerationMagnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  /// Deliberately high, configurable candidate threshold for foreground demo use.
  static const double impactCandidateThreshold = 30.0;
}
