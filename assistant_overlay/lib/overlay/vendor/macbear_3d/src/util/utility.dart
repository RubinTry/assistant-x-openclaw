import 'dart:typed_data';

// Macbear3D engine
import '../m3_internal.dart';

/// Matrix4 extension for orthographic inverse
extension Matrix4Extension on Matrix4 {
  Matrix4 orthoInverse() {
    // (1/3): inverse rotation by transposed
    Matrix3 rotInv = getRotation().transposed();

    // (2/3): inverse translation by negative
    Vector3 tInv = -(rotInv * getTranslation());

    // (3/3): inverse matrix only for ortho
    Matrix4 retMat = Matrix4.identity();
    retMat.setRotation(rotInv);
    retMat.setTranslation(tInv);
    return retMat;
  }

  Vector3 decomposeScale() {
    Vector3 scale = Vector3.zero();

    scale.x = Vector3(storage[0], storage[4], storage[8]).length;
    scale.y = Vector3(storage[1], storage[5], storage[9]).length;
    scale.z = Vector3(storage[2], storage[6], storage[10]).length;

    return scale;
  }
}

// Macbear note:
// for Android blank issue
// use these functions to convert TypedData to NativeArray
/*
//---------------------------------------
// flutter_angle 3.9.0
//---------------------------------------
/// Float32List → NativeArray<num>（aka Float32Array）
Float32Array toF32List(Float32List list) {
  return Float32Array.fromList(list);
}

/// Uint32List → NativeArray<num>（aka Uint32Array）
Uint32Array toU32List(Uint32List list) {
  return Uint32Array.fromList(list);
}

/// Uint16List → NativeArray<num>（aka Uint16Array）
Uint16Array toU16List(Uint16List list) {
  return Uint16Array.fromList(list);
}

/// Uint8List → NativeArray<num>（aka Uint8Array）
Uint8Array toU8List(Uint8List list) {
  return Uint8Array.fromList(list);
}

*/

//---------------------------------------
// flutter_angle 4.0.0
//---------------------------------------
Float32List toF32List(Float32List list) {
  return list;
}

Uint32List toU32List(Uint32List list) {
  return list;
}

Uint16List toU16List(Uint16List list) {
  return list;
}

Uint8List toU8List(Uint8List list) {
  return list;
}
