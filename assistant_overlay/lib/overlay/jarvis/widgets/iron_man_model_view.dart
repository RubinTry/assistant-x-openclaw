import 'package:flutter/material.dart' hide Colors, Matrix4;
import 'package:vector_math/vector_math.dart';

import '../../vendor/macbear_3d/macbear_3d.dart';

class IronManModelStyle {
  const IronManModelStyle({
    this.palette = const <Color>[
      Color(0xFF0D67BC),
      Color(0xFF8CC1FA),
      Color(0xFFBFE7FF),
      Color(0xFF6EB9FF),
      Color(0xFF0A4F91),
    ],
    this.opacity = 0.82,
    this.glowColor = const Color(0xFF79D9FF),
    this.glowIntensity = 0.24,
    this.glowScale = 1.045,
    this.spinSpeed = 0.628,
  });

  final List<Color> palette;
  final double opacity;
  final Color glowColor;
  final double glowIntensity;
  final double glowScale;
  final double spinSpeed;

  Vector4 colorAt(int index) {
    if (palette.isEmpty) {
      return _toVector4(const Color(0xFF8CC1FA), opacity);
    }
    return _toVector4(palette[index % palette.length], opacity);
  }

  Vector4 get glowVector => _toVector4(glowColor, glowIntensity);

  static Vector4 _toVector4(Color color, double alphaOverride) {
    return Vector4(color.r, color.g, color.b, alphaOverride.clamp(0.0, 1.0));
  }
}

class IronManModelView extends StatefulWidget {
  const IronManModelView({super.key, this.style = const IronManModelStyle()});

  final IronManModelStyle style;

  @override
  State<IronManModelView> createState() => _IronManModelViewState();
}

class _IronManModelViewState extends State<IronManModelView> {
  @override
  void initState() {
    super.initState();
    M3AppEngine.instance.onDidInit = _onDidInit;
  }

  Future<void> _onDidInit() async {
    final appEngine = M3AppEngine.instance;
    final shaderOptions = appEngine.renderEngine.options.shader;
    shaderOptions.pbr = false;
    shaderOptions.ibl = false;
    shaderOptions.perPixel = true;
    appEngine.renderEngine.options.debug.showHelpers = false;
    appEngine.renderEngine.options.debug.showStats = false;
    await appEngine.setScene(IronManModelScene(style: widget.style));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final mediaQuery = MediaQuery.of(context);
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: MediaQuery(
              data: mediaQuery.copyWith(size: Size.square(side)),
              child: const M3View(),
            ),
          ),
        );
      },
    );
  }
}

class IronManModelScene extends M3Scene {
  IronManModelScene({required this.style});

  final IronManModelStyle style;

  M3Entity? _ironMan;
  M3Entity? _glowShell;
  double _spinAngle = 0;

  @override
  Future<void> load() async {
    if (isLoaded) return;
    await super.load();

    inputController = null;
    M3AppEngine.backgroundColor = Vector4(0.03, 0.08, 0.14, 0);

    final mesh = await M3Mesh.load('assets/iron-man_mark_7.glb');
    mesh.skin = null;
    mesh.animator = null;
    _applyHudArmorPalette(mesh);
    _centerMeshGeometry(mesh);

    if (style.glowIntensity > 0) {
      final glowMesh = mesh.clone();
      _applyGlowMaterial(glowMesh);
      _glowShell = addMesh(glowMesh, Vector3.zero());
      _glowShell!
        ..scale = Vector3.all(0.001 * style.glowScale)
        ..rotation = Quaternion.identity()
        ..color = Vector4(1.0, 1.0, 1.0, 1.0);
    }

    _ironMan = addMesh(mesh, Vector3.zero());
    _ironMan!
      ..scale = Vector3.all(0.001)
      ..rotation = Quaternion.identity()
      ..color = Vector4(1.0, 1.0, 1.0, 1.0);

    camera.setLookat(Vector3(0, 0.25, 3.3), Vector3(0, 0, 0), Vector3(0, 1, 0));
  }

  void setIronManYawPitchRoll(double yaw, double pitch, double roll) {
    final pose =
        Quaternion.axisAngle(Vector3(0, 1, 0), yaw) *
        Quaternion.axisAngle(Vector3(1, 0, 0), pitch) *
        Quaternion.axisAngle(Vector3(0, 0, 1), roll);
    _glowShell?.rotation = pose;
    _ironMan?.rotation = pose;
  }

  @override
  void update(double delta) {
    super.update(delta);
    _spinAngle += delta * style.spinSpeed;
    setIronManYawPitchRoll(_spinAngle, 0, 0);
  }

  void _applyHudArmorPalette(M3Mesh mesh) {
    for (var i = 0; i < mesh.subMeshes.length; i++) {
      final material = mesh.subMeshes[i].mtr;
      final color = style.colorAt(i);
      material.diffuse.setFrom(color);
      material.diffuseTexture = M3Texture.createSolidColor(
        Vector4(color.x, color.y, color.z, 1.0),
      );
      material.alphaMode = M3AlphaMode.blend;
      material.specular.setValues(0.75, 0.9, 1.0);
      material.shininess = 96;
      material.metallic = 0.85;
      material.roughness = 0.22;
      material.reflection = 0.18;
    }
  }

  void _applyGlowMaterial(M3Mesh mesh) {
    final color = style.glowVector;
    for (var i = 0; i < mesh.subMeshes.length; i++) {
      final material = mesh.subMeshes[i].mtr;
      material.diffuse.setFrom(color);
      material.diffuseTexture = M3Texture.createSolidColor(
        Vector4(color.x, color.y, color.z, 1.0),
      );
      material.alphaMode = M3AlphaMode.blend;
      material.specular.setZero();
      material.shininess = 1;
      material.metallic = 0;
      material.roughness = 1;
      material.reflection = 0;
      material.renderOrder = -1;
    }
  }

  void _centerMeshGeometry(M3Mesh mesh) {
    if (mesh.subMeshes.isEmpty) return;

    final bounds = Aabb3();
    bounds.min.setValues(double.infinity, double.infinity, double.infinity);
    bounds.max.setValues(
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    );

    final vertex = Vector3.zero();
    for (final subMesh in mesh.subMeshes) {
      final localAabb = subMesh.geom.localBounding.aabb;
      for (var i = 0; i < 8; i++) {
        vertex.setValues(
          (i & 1) == 0 ? localAabb.min.x : localAabb.max.x,
          (i & 2) == 0 ? localAabb.min.y : localAabb.max.y,
          (i & 4) == 0 ? localAabb.min.z : localAabb.max.z,
        );
        subMesh.localMatrix.transform3(vertex);
        bounds.hullPoint(vertex);
      }
    }

    final center = bounds.center;
    final recenter = Matrix4.identity()..translateByVector3(-center);
    mesh.initMatrix = recenter * mesh.initMatrix;
  }
}
