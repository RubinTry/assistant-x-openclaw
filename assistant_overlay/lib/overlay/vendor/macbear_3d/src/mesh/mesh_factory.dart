import '../m3_internal.dart';

extension M3MeshFactory on M3Mesh {
  /// create axis-dot mesh
  static M3Mesh createAxisDot() {
    List<M3SubMesh> subMeshes = [];
    final mtrRed = M3Material()
      ..diffuse = Vector4(1, 0, 0, 1)
      ..setMatte();
    final mtrGreen = mtrRed.clone()..diffuse = Vector4(0, 1, 0, 1);
    final mtrBlue = mtrRed.clone()..diffuse = Vector4(0, 0, 1, 1);

    // 3 arrows
    final arrowX = M3SubMesh(M3PyramidGeom(0.08, 0.08, 0.4, axis: M3Axis.x), material: mtrRed);
    arrowX.localMatrix.translateByVector3(Vector3(0.25, 0, 0));
    subMeshes.add(arrowX);
    final arrowY = M3SubMesh(M3PyramidGeom(0.08, 0.08, 0.4, axis: M3Axis.y), material: mtrGreen);
    arrowY.localMatrix.translateByVector3(Vector3(0, 0.25, 0));
    subMeshes.add(arrowY);
    final arrowZ = M3SubMesh(M3PyramidGeom(0.08, 0.08, 0.4, axis: M3Axis.z), material: mtrBlue);
    arrowZ.localMatrix.translateByVector3(Vector3(0, 0, 0.25));
    subMeshes.add(arrowZ);

    final dotXYZ = M3Mesh(null);
    dotXYZ.subMeshes = subMeshes;
    return dotXYZ;
  }

  /// create axis-gizmo mesh
  static M3Mesh createAxisGizmo() {
    List<M3SubMesh> subMeshes = [];
    final mtrRed = M3Material()
      ..diffuse = Vector4(1, 0, 0, 1)
      ..setMatte();
    final mtrGreen = mtrRed.clone()..diffuse = Vector4(0, 1, 0, 1);
    final mtrBlue = mtrRed.clone()..diffuse = Vector4(0, 0, 1, 1);
    final mtrWhite = mtrRed.clone()..diffuse = Vector4(1, 1, 1, 1);

    // alpha blend
    final base = 0.8;
    final alpha = 0.5;
    final mtrRedAlpha = mtrRed.clone()
      ..diffuse = Vector4(base, 0, 0, alpha)
      ..alphaMode = M3AlphaMode.blend;
    final mtrGreenAlpha = mtrRed.clone()
      ..diffuse = Vector4(0, base, 0, alpha)
      ..alphaMode = M3AlphaMode.blend;
    final mtrBlueAlpha = mtrRed.clone()
      ..diffuse = Vector4(0, 0, base, alpha)
      ..alphaMode = M3AlphaMode.blend;

    // 3 axes: positive
    final axisX = M3SubMesh(M3Resources.unitCube, material: mtrRed);
    final axisScale = 5.0;
    axisX.localMatrix
      ..translateByVector3(Vector3(axisScale * 0.5, 0, 0))
      ..scaleByVector3(Vector3(axisScale, 0.1, 0.1));
    subMeshes.add(axisX);
    final axisY = M3SubMesh(M3Resources.unitCube, material: mtrGreen);
    axisY.localMatrix
      ..translateByVector3(Vector3(0, axisScale * 0.5, 0))
      ..scaleByVector3(Vector3(0.1, axisScale, 0.1));
    subMeshes.add(axisY);
    final axisZ = M3SubMesh(M3Resources.unitCube, material: mtrBlue);
    axisZ.localMatrix
      ..translateByVector3(Vector3(0, 0, axisScale * 0.5))
      ..scaleByVector3(Vector3(0.1, 0.1, axisScale));
    subMeshes.add(axisZ);

    // 3 axes: negative
    final axisXAlpha = M3SubMesh(M3Resources.unitCube, material: mtrRedAlpha);
    axisXAlpha.localMatrix
      ..translateByVector3(Vector3(-axisScale * 0.5, 0, 0))
      ..scaleByVector3(Vector3(axisScale, 0.1, 0.1));
    subMeshes.add(axisXAlpha);
    final axisYAlpha = M3SubMesh(M3Resources.unitCube, material: mtrGreenAlpha);
    axisYAlpha.localMatrix
      ..translateByVector3(Vector3(0, -axisScale * 0.5, 0))
      ..scaleByVector3(Vector3(0.1, axisScale, 0.1));
    subMeshes.add(axisYAlpha);
    final axisZAlpha = M3SubMesh(M3Resources.unitCube, material: mtrBlueAlpha);
    axisZAlpha.localMatrix
      ..translateByVector3(Vector3(0, 0, -axisScale * 0.5))
      ..scaleByVector3(Vector3(0.1, 0.1, axisScale));
    subMeshes.add(axisZAlpha);

    // 3 arrows
    final arrowScale = Vector3(0.4, 0.4, 0.4);
    final arrowX = M3SubMesh(M3PyramidGeom(1, 1, 1, axis: M3Axis.x), material: mtrRed);
    arrowX.localMatrix
      ..translateByVector3(Vector3(axisScale, 0, 0))
      ..scaleByVector3(arrowScale);
    subMeshes.add(arrowX);
    final arrowY = M3SubMesh(M3PyramidGeom(1, 1, 1, axis: M3Axis.y), material: mtrGreen);
    arrowY.localMatrix
      ..translateByVector3(Vector3(0, axisScale, 0))
      ..scaleByVector3(arrowScale);
    subMeshes.add(arrowY);
    final arrowZ = M3SubMesh(M3PyramidGeom(1, 1, 1, axis: M3Axis.z), material: mtrBlue);
    arrowZ.localMatrix
      ..translateByVector3(Vector3(0, 0, axisScale))
      ..scaleByVector3(arrowScale);
    subMeshes.add(arrowZ);

    final origin = M3SubMesh(M3Resources.debugDot, material: mtrWhite);
    subMeshes.add(origin);

    final axisGizmo = M3Mesh(null);
    axisGizmo.subMeshes = subMeshes;
    return axisGizmo;
  }

  /// create frustum mesh
  static M3Mesh createFrustum() {
    final sz = 1.98;
    final planePositiveXY = M3PlaneGeom(sz, sz, widthSegments: 6, heightSegments: 4, axis: M3Axis.z);
    final planePositiveXZ = M3PlaneGeom(sz, sz, widthSegments: 3, heightSegments: 1, axis: M3Axis.y);
    final planePositiveYZ = M3PlaneGeom(sz, sz, widthSegments: 1, heightSegments: 2, axis: M3Axis.x);
    final planeNegativeXY = M3PlaneGeom(sz, sz, axis: M3Axis.z, flipFace: true);
    final planeNegativeXZ = M3PlaneGeom(sz, sz, widthSegments: 3, heightSegments: 1, axis: M3Axis.y, flipFace: true);
    final planeNegativeYZ = M3PlaneGeom(sz, sz, widthSegments: 1, heightSegments: 2, axis: M3Axis.x, flipFace: true);

    final mtrRed = M3Material()
      ..diffuse = Vector4(1, 0, 0, 1)
      ..setMatte();
    final mtrGreen = mtrRed.clone()..diffuse = Vector4(0, 1, 0, 1);
    final mtrBlue = mtrRed.clone()..diffuse = Vector4(0, 0, 1, 1);
    final mtrSkyblue = mtrRed.clone()..diffuse = Vector4(0, 1, 1, 1);

    List<M3SubMesh> subMeshes = [];
    // XY planes
    final positiveXY = M3SubMesh(planePositiveXY, material: mtrSkyblue);
    positiveXY.localMatrix.translateByVector3(Vector3(0, 0, 1));
    subMeshes.add(positiveXY);
    final negativeXY = M3SubMesh(planeNegativeXY, material: mtrBlue);
    negativeXY.localMatrix.translateByVector3(Vector3(0, 0, -1));
    subMeshes.add(negativeXY);

    // XZ planes
    final positiveXZ = M3SubMesh(planePositiveXZ, material: mtrGreen);
    positiveXZ.localMatrix.translateByVector3(Vector3(0, 1, 0));
    subMeshes.add(positiveXZ);
    final negativeXZ = M3SubMesh(planeNegativeXZ, material: mtrGreen);
    negativeXZ.localMatrix.translateByVector3(Vector3(0, -1, 0));
    subMeshes.add(negativeXZ);

    // YZ planes
    final positiveYZ = M3SubMesh(planePositiveYZ, material: mtrRed);
    positiveYZ.localMatrix.translateByVector3(Vector3(1, 0, 0));
    subMeshes.add(positiveYZ);
    final negativeYZ = M3SubMesh(planeNegativeYZ, material: mtrRed);
    negativeYZ.localMatrix.translateByVector3(Vector3(-1, 0, 0));
    subMeshes.add(negativeYZ);

    final frustum = M3Mesh(null);
    frustum.subMeshes = subMeshes;
    return frustum;
  }

  void draw(M3Program prog, M3Camera camera, Matrix4 worldMatrix, {M3FillMode fillMode = .solid}) {
    Vector4 color = Vector4.all(1.0);
    for (final sub in subMeshes) {
      Matrix4 subMatrix = worldMatrix * sub.localMatrix;
      prog.setMatrices(camera, subMatrix);
      prog.setMaterial(sub.mtr, color);
      sub.geom.draw(prog, fillMode: fillMode);
    }
  }
}
