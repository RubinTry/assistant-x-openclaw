part of 'light.dart';

class M3ShadowCascade {
  Matrix4 projectionMatrix = Matrix4.identity();
  double atlasBiasV = 0.0; // texture bias-V (CSM shader use 1 shadowmap, 1 pass)
  double atlasScaleV = 1.0; // texture scale-V (CSM shader use 1 shadowmap, 1 pass)

  @override
  String toString() {
    return 'atlas: bias=$atlasBiasV, scale=$atlasScaleV';
  }
}

/// directional light
class M3DirectionalLight extends M3Light {
  bool isCameraAligned = true; // align camera to light
  double shadowNormalBias = 0.05;
  double csmPaddingNear = 2.0;
  double csmPaddingFar = 2.0;

  List<M3ShadowCascade> cascades = [];
  M3Camera lightViewer = M3Camera();

  M3DirectionalLight() {
    lightViewer.setLookat(Vector3(2, 0, 8), Vector3.zero(), Vector3(0, 0, 1));

    // isCameraAligned = false;
  }

  /// get light direction
  Vector3 getDirection() {
    return lightViewer.viewMatrix.getRow(2).xyz; // Z axis
  }

  void updateShadowCascades(M3Camera cam) {
    if (cam.csmCount == 0) {
      cascades.clear();
      return;
    }

    final splits = cam.csmSplitDistances;
    final int count = splits.length - 1;

    if (isCameraAligned) {
      // Calculate camera frustum center in world space
      final double near = splits.first;
      final double far = splits.last;
      final double midZ = (near + far) / 2.0;

      // Centroid in camera space (negative Z is forward)
      final Vector3 centroidCam = Vector3(0, 0, -midZ);
      final Vector3 centroidWorld = cam.cameraToWorldMatrix.transform3(centroidCam);

      // maintain light direction (Z-axis of viewMatrix is backward direction)
      final Vector3 dirLightBackward = lightViewer.viewMatrix.getRow(2).xyz;
      // update light eye/target to center on frustum
      final double dist = lightViewer.distanceToTarget;
      lightViewer.target.setFrom(centroidWorld);
      lightViewer.position.setFrom(lightViewer.target + dirLightBackward * dist);

      // check for gimbal lock (singularity when light direction is parallel to up vector)
      Vector3 safeUp = -cam.viewMatrix.getRow(2).xyz;
      if (dirLightBackward.dot(safeUp).abs() > 0.99) {
        // if parallel to camera up, use camera backward or right as fallback
        safeUp = cam.viewMatrix.getRow(1).xyz; // camera backward
        if (dirLightBackward.dot(safeUp).abs() > 0.99) {
          safeUp = cam.viewMatrix.getRow(0).xyz; // camera right
        }
      }
      lightViewer.setLookat(lightViewer.position, lightViewer.target, safeUp);
    }

    if (cascades.length != count) {
      cascades = List.generate(count, (_) => M3ShadowCascade());
    }

    final double aspect = cam.viewportW / cam.viewportH;
    final double tanHalfFov = tan(radians(cam.degreeFovY) / 2.0);
    final Matrix4 camToWorld = cam.cameraToWorldMatrix;
    final Matrix4 worldToLight = lightViewer.viewMatrix;

    // 1. Calculate the overall Z-range for the entire camera frustum in light space
    // This ensures all cascades share the same near/far clipping planes for consistency.
    double overallMinZ = double.infinity;
    double overallMaxZ = -double.infinity;

    // Corner points of the full camera frustum (near and far splits)
    final List<Vector3> fullFrustumCorners = [];
    for (double z in [-cam.nearClip, -cam.farClip]) {
      double h = z.abs() * tanHalfFov;
      double w = h * aspect;
      fullFrustumCorners.add(Vector3(w, h, z));
      fullFrustumCorners.add(Vector3(-w, h, z));
      fullFrustumCorners.add(Vector3(w, -h, z));
      fullFrustumCorners.add(Vector3(-w, -h, z));
    }

    for (var corner in fullFrustumCorners) {
      final v = corner.clone()
        ..applyMatrix4(camToWorld)
        ..applyMatrix4(worldToLight);
      overallMinZ = min(overallMinZ, v.z);
      overallMaxZ = max(overallMaxZ, v.z);
    }

    // Add padding to avoid clipping objects that cast shadows into the frustum
    final double depthNear = -overallMaxZ - csmPaddingNear; // padding for casters behind light
    final double depthFar = -overallMinZ + csmPaddingFar;

    for (int i = 0; i < count; i++) {
      final double near = splits[i];
      final double far = splits[i + 1];

      // 2. Use Bounding Sphere for Stability
      // Calculate the center and radius of the frustum split in camera space
      // For more stability, we use a sphere that encloses the frustum split.
      // The radius of this sphere depends only on 'near' and 'far', making it invariant to camera rotation.

      // Center of the split along Z axis in camera space
      final double midZ = (near + far) / 2.0;
      final Vector3 splitCenterCam = Vector3(0, 0, -midZ);

      // Far corner of the split to calculate radius
      final double hFar = far * tanHalfFov;
      final double wFar = hFar * aspect;
      final Vector3 farCornerCam = Vector3(wFar, hFar, -far);
      final double radius = (farCornerCam - splitCenterCam).length;

      // Transform center to light space
      final Vector3 splitCenterLight = splitCenterCam.clone()
        ..applyMatrix4(camToWorld)
        ..applyMatrix4(worldToLight);

      // AABB in light space based on the bounding sphere (for X and Y)
      // This AABB is square and centered on the split center, preventing shimmering.
      double minX = splitCenterLight.x - radius;
      double maxX = splitCenterLight.x + radius;
      double minY = splitCenterLight.y - radius;
      double maxY = splitCenterLight.y + radius;

      // 3. Texel Snapping
      final double shadowResolutionX = shadowMap!.mapW.toDouble();
      final double atlasScaleV = cascades[i].atlasScaleV;
      final double shadowResolutionY = shadowMap!.mapH.toDouble() * atlasScaleV;

      double worldUnitsPerTexelX = (maxX - minX) / shadowResolutionX;
      double worldUnitsPerTexelY = (maxY - minY) / shadowResolutionY;

      minX = (minX / worldUnitsPerTexelX).floorToDouble() * worldUnitsPerTexelX;
      maxX = minX + (radius * 2.0 / worldUnitsPerTexelX).ceilToDouble() * worldUnitsPerTexelX;

      minY = (minY / worldUnitsPerTexelY).floorToDouble() * worldUnitsPerTexelY;
      maxY = minY + (radius * 2.0 / worldUnitsPerTexelY).ceilToDouble() * worldUnitsPerTexelY;

      // Build stable orthographic projection Matrix
      cascades[i].projectionMatrix = makeOrthographicMatrix(minX, maxX, minY, maxY, depthNear, depthFar);
    }
    _updateCascadeAtlasV();
  }

  void _updateCascadeAtlasV() {
    final int atlasCount = cascades.length;
    if (atlasCount <= 1) {
      return;
    }

    double biasV = 0;
    int maxPow2 = 1;
    // max-pow2 must power of 2 and (maxPow2 <= numSplit)
    while (maxPow2 < atlasCount) {
      maxPow2 *= 2;
    }

    // split-1: (1)
    // split-2: (1/2, 1/2)
    // split-3: (2/4, 1/4, 1/4)
    // split-4: (1/4, 1/4, 1/4, 1/4)
    for (int i = 0; i < atlasCount; i++) {
      cascades[i].atlasScaleV = (i < maxPow2 - atlasCount) ? 2.0 / maxPow2 : 1.0 / maxPow2;
      cascades[i].atlasBiasV = biasV;
      biasV += cascades[i].atlasScaleV;
    }
  }

  @override
  void drawHelper(M3Program prog, M3Camera viewer) {
    super.drawHelper(prog, viewer);

    if (cascades.isNotEmpty) {
      M3Material mtrHelper = M3Material();
      final colors = [Colors.red, Colors.green, Colors.blue, Colors.white];
      for (int i = cascades.length - 1; i >= 0; i--) {
        final color = colors[i % colors.length];
        color.a = 0.33;
        final crop = cascades[i];
        // camera frustum split
        final frustumMatrix = Matrix4.inverted(crop.projectionMatrix * lightViewer.viewMatrix);
        prog.setMaterial(mtrHelper, color);
        prog.setMatrices(viewer, frustumMatrix);
        M3Resources.debugFrustum.draw(prog, fillMode: .wireframe);

        // far-clip plane
        final clipMatrix = Matrix4.identity()
          ..rotateX(pi / 2)
          ..setTranslation(Vector3(0, 0, -1));
        final farMatrix = Matrix4.inverted(clipMatrix * crop.projectionMatrix * lightViewer.viewMatrix);
        prog.setMatrices(viewer, farMatrix);
        M3Resources.debugView.draw(prog, fillMode: .solid);
      }
    }
  }
}
