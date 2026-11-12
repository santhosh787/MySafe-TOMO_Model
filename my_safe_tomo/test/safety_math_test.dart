import 'package:flutter_test/flutter_test.dart';
import 'package:my_safe_tomo/utils/safety_math.dart';

void main() {
  group('SafetyMath', () {
    test('computes acceleration magnitude', () {
      expect(SafetyMath.accelerationMagnitude(3, 4, 0), 5);
    });

    test('keeps a normal gravity magnitude below the impact candidate threshold', () {
      final gravity = SafetyMath.accelerationMagnitude(0, 0, 9.81);
      expect(gravity, lessThan(SafetyMath.impactCandidateThreshold));
    });

    test('does not treat the candidate threshold as an automatic SOS', () {
      expect(SafetyMath.impactCandidateThreshold, 30.0);
    });
  });
}
