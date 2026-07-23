import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';

/// height field data for physics
/// M3PlaneGeom, M3TerrainGeom can generate height field data
class M3HeightField {
  Float32List data;
  Vector2 cellSize;
  double heightScale;
  M3HeightField(this.data, this.cellSize, this.heightScale);
}
