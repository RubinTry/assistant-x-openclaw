import 'package:flutter/material.dart' hide Matrix4;

// Macbear3D engine
import '../m3_internal.dart' hide Colors;

enum M3Axis { x, y, z }

class M3Constants {
  // POD should rotate axisX 90 degree: up from axisY(POD) to axisZ(3dsmax); POD(x,y,z) to 3dsmax(x,-z,y)
  // matrix rotate by X-axis: rotationX(-PI_HALF)
  static final Matrix3 rotXNeg90 = Matrix3.columns(
    Vector3(1, 0, 0), // X
    Vector3(0, 0, -1), // -Z
    Vector3(0, 1, 0), // Y
  );

  // matrix rotate by X-axis: rotationX(PI_HALF)
  static final Matrix3 rotXPos90 = Matrix3.columns(
    Vector3(1, 0, 0), // X
    Vector3(0, 0, 1), // Z
    Vector3(0, -1, 0), // Y
  );

  static final biasMatrix = Matrix4.columns(
    Vector4(0.5, 0, 0, 0),
    Vector4(0, 0.5, 0, 0),
    Vector4(0, 0, 0.5, 0),
    Vector4(0.5, 0.5, 0.5, 1),
  );

  // default material
  static final M3Material mtrDefault = M3Material()
    ..diffuse = Vector4(0.75, 0.75, 0.75, 1.0)
    ..specular = Vector3(0.2, 0.2, 0.2)
    ..shininess = 32;

  // 高反射、高光集中的銀色金屬
  static final M3Material mtrMetal = M3Material()
    ..diffuse = Vector4(0.4, 0.4, 0.4, 1.0)
    ..specular = Vector3(0.6, 0.6, 0.6)
    ..shininess = 128
    ..reflection = 0.8;

  static final M3Material mtrWood = M3Material()
    ..diffuse = Vector4(0.65, 0.45, 0.25, 1.0)
    ..specular = Vector3(0.2, 0.2, 0.2)
    ..shininess = 32;

  // blinn plastic
  static final M3Material mtrPlastic = M3Material()
    ..diffuse = Vector4(0.65, 0.65, 0.65, 1.0)
    ..specular = Vector3(0.2, 0.2, 0.2)
    ..shininess = 64
    ..reflection = 0.4;

  // 半透明、高反射的清玻璃
  static final M3Material mtrGlass = M3Material()
    ..diffuse = Vector4(0.0, 0.0, 0.0, 0.2)
    ..specular = Vector3(0.5, 0.5, 0.5)
    ..shininess = 64
    ..reflection = 0.9;

  static final Vector3 colorLake = Vector3(0.30, 0.45, 0.40);
  static final Vector3 colorMountainLake = Vector3(0.35, 0.55, 0.60);
  static final Vector3 colorBeach = Vector3(0.31, 0.75, 0.78);
  static final Vector3 colorOcean = Vector3(0.23, 0.44, 0.48);
  static final Vector3 colorNight = Vector3(0.12, 0.15, 0.20);
  static final Vector3 colorDusk = Vector3(0.85, 0.70, 0.55);
  static final Vector3 colorGray = Vector3(0.70, 0.72, 0.75);
  static final Vector3 colorSkyBlue = Vector3(0.78, 0.85, 0.91);

  // water tint color
  static final Vector3 colorWaterTint = Vector3(0.90, 0.97, 1.00);
  static final Vector3 colorWaterTintLake = Vector3(0.94, 0.99, 1.00);
  static final Vector3 colorWaterTintSea = Vector3(0.80, 1.00, 1.00);

  // dart format off
  static final List<int> permutation = [
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
    140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
    247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
    57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
    74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
    60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
    65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
    200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
    52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
    207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
    119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
    129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
    218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
    81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
    184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
    222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180
  ];
  // dart format on
}

// package: local font asset
class M3Package {
  static String? name;

  // fixed width font
  static TextStyle textStyleRobotoMono({double fontSize = 32}) {
    TextStyle style = TextStyle(
      fontFamily: 'RobotoMono',
      package: name, // 強制使用 package 命名空間
      fontSize: fontSize,
      color: Colors.white,
      letterSpacing: 1.1, // 這裡設定字距，數值越大間隔越開
      height: 1.1,
      // shadows: const [Shadow(blurRadius: 1, offset: Offset(1, 1))],
    );

    return style;
  }

  static String asset(String path) {
    return 'packages/$name/$path';
  }
}
