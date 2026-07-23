// Macbear3D engine
import '../m3_internal.dart';

/// Layer for water wave animation
class M3WaterFlowLayer {
  Vector2 offset = Vector2.zero();
  Vector2 scale = Vector2.all(1.0);
  Vector2 velocity = Vector2.zero();
}

enum M3WaterCameraState { aboveWater, onSurface, underwater }

/// water effect, using plane reflection / refraction.
class M3Water extends M3Entity {
  M3ProgramWater get progWater => M3Resources.programWater!; // debug: programMirror
  M3ProgramWaterCSM get progWaterCSM => M3Resources.programWaterCSM!;

  Plane surfacePlane = Plane.components(0, 0, 1, 0);
  M3Texture normalMap = M3Resources.texNormal; // normal-map for water wave distortion
  double waveDistortion = 10.0;
  double reflectionDepthBias = 0.8;
  late M3Scene scene;
  // camera view state relative to water surface
  M3WaterCameraState cameraState = .aboveWater;

  static M3Mesh createWaterSurface({
    double width = 400,
    double height = 400,
    int widthSegments = 40,
    int heightSegments = 40,
    Vector2? uvScale,
  }) {
    final mtr = M3Material()
      ..setGlossy()
      ..metallic = 0.3
      ..reflection = 0.3;
    final waterMesh = M3Mesh(
      M3PlaneGeom(width, height, widthSegments: widthSegments, heightSegments: heightSegments, uvScale: uvScale),
      material: mtr,
    );

    return waterMesh;
  }

  M3Material get waterMaterial => mesh.subMeshes[0].mtr;

  // water surface render pass
  final M3PlanarReflection reflectionPass;
  final M3PlanarReflection refractionPass;

  // fog part:
  double startFog = 3; // plane fog start distance

  // for bump flow animation
  M3WaterFlowLayer flow0 = M3WaterFlowLayer()
    ..scale = Vector2.all(3)
    ..velocity = Vector2(0.016, -0.006);
  M3WaterFlowLayer flow1 = M3WaterFlowLayer()
    ..scale = Vector2.all(7)
    ..velocity = Vector2(0.025, -0.03);

  M3Water({M3Mesh? waterMesh, bool useReflection = true, bool useRefraction = true})
    : reflectionPass = M3PlanarReflection(),
      refractionPass = M3PlanarReflection(),
      super(mesh: waterMesh ?? createWaterSurface()) {
    // reflection/refraction enable state
    reflectionPass.enable = useReflection;
    refractionPass.enable = useRefraction;

    // water tint color
    final tint = M3Constants.colorBeach;
    setWaterTint(Vector4(tint.x, tint.y, tint.z, 0.6));
  }

  bool get reflectionEnabled => reflectionPass.enable;

  set reflectionEnabled(bool value) {
    reflectionPass.enable = value;
    if (value) {
      reflectionPass.resize(M3AppEngine.instance.appWidth, M3AppEngine.instance.appHeight);
    }
  }

  bool get refractionEnabled => refractionPass.enable;

  set refractionEnabled(bool value) {
    refractionPass.enable = value;
    if (value) {
      refractionPass.resize(M3AppEngine.instance.appWidth, M3AppEngine.instance.appHeight);
    }
  }

  /// water surface tint color
  void setWaterTint(Vector4 tint) {
    color.setFrom(tint);
  }

  /// plane equation: ax + by + cz + d = 0
  void setSurfacePlane({Vector3? normal, double constant = 0}) {
    final Vector3 n = normal ?? surfacePlane.normal;
    surfacePlane.setFromComponents(n.x, n.y, n.z, constant);
    reflectionPass.clipPlane.setFromComponents(n.x, n.y, n.z, constant);
    refractionPass.clipPlane.setFromComponents(n.x, n.y, n.z, constant);

    position = Vector3(0, 0, -constant);
  }

  void resize(int width, int height) {
    reflectionPass.resize(width, height);
    refractionPass.resize(width, height);
  }

  @override
  void update(double dt) {
    super.update(dt);

    flow0.offset += flow0.velocity * dt;
    flow0.offset.x %= 1.0;
    flow0.offset.y %= 1.0;

    flow1.offset += flow1.velocity * dt;
    flow1.offset.x %= 1.0;
    flow1.offset.y %= 1.0;

    cameraState = _getCameraState(scene.camera);
  }

  /// camera near to water, return true if camera is above water
  bool isCameraNearWater(M3Camera camera) {
    final state = _getCameraState(camera, epsilon: camera.nearClip * 0.5);
    return (state != .aboveWater);
  }

  /// get water camera state from camera position to water surface
  M3WaterCameraState _getCameraState(M3Camera camera, {double epsilon = 0.03}) {
    final double dist = surfacePlane.distanceToVector3(camera.position);
    M3WaterCameraState result = .onSurface;
    if (dist < -epsilon) {
      result = .underwater;
    }

    if (dist > epsilon) {
      result = .aboveWater;
    }

    return result;
  }

  /// capture reflection / refraction fbos
  void captureWater() {
    Vector3 n = surfacePlane.normal.clone();
    double d = surfacePlane.constant;

    // fog from water surface (horizon)
    scene.fog.plane.setFromComponents(n.x, n.y, n.z, d + startFog);

    // if underwater, reflection is water fog, refraction is scene fog
    switch (cameraState) {
      case .underwater:
        n = -n;
        d = -d;
        break;
      case .onSurface:
        return; // no reflection and refraction when on surface
      case .aboveWater:
        break;
    }

    // capture reflection
    reflectionPass.clipPlane.setFromComponents(n.x, n.y, n.z, d);
    reflectionPass.captureReflection(scene);

    // capture refraction
    refractionPass.clipPlane.setFromComponents(n.x, n.y, n.z, d);
    refractionPass.captureRefraction(scene);
  }

  /// render water surface
  void render({M3FillMode fillMode = .solid}) {
    final viewer = scene.camera;
    if (fillMode == .solid) {
      RenderingContext gl = M3AppEngine.instance.renderEngine.gl;
      gl.enable(WebGL.BLEND);
      gl.blendFunc(WebGL.SRC_ALPHA, WebGL.ONE_MINUS_SRC_ALPHA); // alpha blending
      gl.depthMask(false); // Don't write to depth buffer in blending pass
      gl.disable(WebGL.CULL_FACE);

      final renderEngine = M3AppEngine.instance.renderEngine;
      bool csmEnabled = renderEngine.isShadowEnabled && scene.dirLight.cascades.isNotEmpty;
      final M3ProgramLighting prog = csmEnabled ? progWaterCSM : progWater;

      gl.useProgram(prog.program);
      prog.attachDirectionalLight(scene.dirLight);
      prog.attachPointLights(scene.pointLights);
      prog.applyUniforms(viewer);
      prog.applyFog(scene.fog);
      (prog as M3WaterShader).bindWater(this);

      // water material: set reflection texture if enabled
      if (reflectionPass.enable) {
        waterMaterial.diffuseTexture = reflectionPass.texture;
      } else {
        waterMaterial.diffuseTexture = M3Resources.texWhite;
      }

      final alpha = 1.0; //water!.waterMaterial.reflection;
      final waterMatrix = worldMatrix;
      prog.setMatrices(viewer, waterMatrix);
      prog.setMaterial(waterMaterial, Vector4(0.0, 1.0, 0.8, alpha));
      prog.setSkinning(null);

      // Call setLightTBN after setMatrices to set tangent-space uniforms and light position correctly
      final normal = (cameraState == .aboveWater) ? surfacePlane.normal : -surfacePlane.normal;
      var tangent = Vector3(1.0, 0.0, 0.0);
      if (tangent.dot(normal).abs() > 0.9) {
        tangent = Vector3(0.0, 1.0, 0.0);
      }
      final binormal = normal.cross(tangent).normalized();
      tangent = binormal.cross(normal).normalized();
      prog.setLightTBN(tangent, binormal, normal);

      // reflection for above water, refraction for below water
      mesh.subMeshes[0].geom.draw(prog);

      // Restore depth state
      gl.depthMask(true);
      gl.enable(WebGL.CULL_FACE);
    } else {
      Vector4 colorSurface;
      switch (cameraState) {
        case .underwater:
          colorSurface = Vector4(1, 0, 0, 0.8);
          break;
        case .onSurface:
          colorSurface = Vector4(0, 1, 0, 0.8);
          break;
        case .aboveWater:
          colorSurface = Vector4(0, 1, 1, 0.8);
          break;
      }

      final progEdge = M3Resources.programSimple!;
      final waterMatrix = worldMatrix;
      progEdge.setMatrices(viewer, waterMatrix);
      progEdge.setMaterial(waterMaterial, colorSurface);
      mesh.subMeshes[0].geom.draw(progEdge, fillMode: .wireframe);
    }
  }

  void debugDraw() {
    final passes = {reflectionPass, refractionPass};

    const ratio = 0.4;
    double x = 8;
    double y = 8;
    double w = 0;
    double h = 0;
    for (final pass in passes) {
      if (pass.enable && pass.visible) {
        w = pass.width * ratio;
        h = pass.height * ratio;
        pass.debugDrawReflection(x, y, w, h);
        x += w + 2;
      }
    }

    // water normal map
    normalMap.debugDraw(x, y, ratio, ratio);
  }

  void dispose() {
    if (normalMap != M3Resources.texNormal) {
      normalMap.dispose();
    }

    reflectionPass.dispose();
    refractionPass.dispose();
  }
}
