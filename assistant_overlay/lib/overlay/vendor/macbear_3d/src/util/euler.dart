import 'dart:math';

import 'package:vector_math/vector_math.dart';

import 'constants.dart';

// Euler: yaw, pitch, roll
class M3Euler {
  // Euler angle by radians
  double yaw = 0.0; // Yaw angle
  double pitch = 0.0; // Pitch angle
  double roll = 0.0; // Roll angle

  void setEuler(double yaw, double pitch, double roll) {
    this.yaw = yaw;
    this.pitch = pitch;
    this.roll = roll;
  }

  void setFrom(M3Euler other) {
    yaw = other.yaw;
    pitch = other.pitch;
    roll = other.roll;
  }

  M3Euler clone() {
    return M3Euler()..setFrom(this);
  }

  void setToward(Vector3 toward) {
    // toward is a normalized vector
    final length = toward.normalize();
    if (length == 0) {
      // invalid vector
      return;
    }
    pitch = -asin(toward.y);
    yaw = atan2(toward.x, toward.z);
    roll = 0.0;
  }

  void normalizeAngle() {
    yaw = yaw % (pi * 2);
    pitch = pitch % (pi * 2);
    roll = roll % (pi * 2);
  }

  Matrix3 getMatrix3() {
    final quat = Quaternion.euler(roll, pitch, yaw);
    Matrix3 retMat3 = M3Constants.rotXPos90 * quat.asRotationMatrix();
    return retMat3;
  }

  @override
  String toString() {
    return 'Euler degree: Yaw=${degrees(yaw).toStringAsFixed(2)}, Pitch=${degrees(pitch).toStringAsFixed(2)}, Roll=${degrees(roll).toStringAsFixed(2)}';
  }
}
