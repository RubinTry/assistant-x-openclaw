part of 'scene.dart';

/// A demonstration scene with cubes, spheres, physics, and a skybox.
class SampleScene extends M3Scene {
  final _geomCube = M3Resources.unitCube;
  final _geomSphere = M3Resources.unitSphere;
  final _geomCylinder = M3CylinderGeom(0.5, 0.5, 1.0, axis: M3Axis.y);
  final _geomPlane = M3PlaneGeom(20.0, 20.0, widthSegments: 50, heightSegments: 50, uvScale: Vector2(10.0, 10.0));

  // constructor
  SampleScene({super.physics});

  @override
  Future<void> load() async {
    if (isLoaded) return;
    await super.load();

    dirLight.lightViewer.setLookat(Vector3(0, 0, 60), Vector3(0, 0, 1), Vector3(0, 1, 0));

    camera.setLookat(Vector3(0, 6, 8), Vector3(0, 0, 2), Vector3(0, 0, 1));
    camera.setEuler(pi / 6, -pi / 5, 0, distance: 10);

    final camera2 = M3Camera();
    int halfView = 3;
    camera2.setViewport(-halfView, -halfView, halfView * 2, halfView * 2, fovy: 40, far: 20);
    camera2.setLookat(Vector3(0, 8, 1), Vector3.zero(), Vector3(0, 0, 1));
    cameras.add(camera2);

    M3Texture texGround = M3Texture.createCheckerboard(
      size: 2,
      lightColor: Vector4(.7, 1, .5, 1),
      darkColor: Vector4(.5, 0.8, .3, 1),
    );
    M3Texture texGrid2 = M3Texture.createCheckerboard(size: 6);
    M3Texture texGrid = M3Texture.createCheckerboard(size: 3);

    // create physics ground rigid body, 4 fences
    physicsSystem.addBox(10, 10, 2, M3RigidBodyDesc.fixed()..position = Vector3(0, 0, -2));

    // ground plane model
    final posGround = Vector3.zero();
    final meshPlane = addMesh(M3Mesh(_geomPlane), posGround);
    meshPlane.mesh.subMeshes[0].mtr
      ..diffuseTexture = texGround
      ..setMatte();

    // axis gizmo
    addMesh(M3Resources.axisGizmoMesh, posGround + Vector3(0, 0, 0));

    List<Vector4> colors = [
      // Colors.lightGray,
      Colors.pink,
      Colors.orange,
      Colors.yellow,
      Colors.lightGreen,
      Colors.cyan,
      Colors.lightBlue,
      Colors.violet,
    ];

    // cube model (dynamic)
    int countX = 4, countY = 4, countZ = 8;
    for (int i = 0; i < countX; i++) {
      for (int j = 0; j < countY; j++) {
        for (int k = 0; k < countZ; k++) {
          final delta = Random().nextDouble() * 0.5 - 0.25 - 2;
          final pos = Vector3(i * 2.0 + delta, j * 2.0 + delta, k * 3.0 + delta);
          pos.z += 3.0; // drop from sky

          final meshColor = colors[k % colors.length];
          M3Mesh mesh;
          M3RigidBody rb;

          // visual entity, rigid body
          switch (k % 3) {
            case 0:
              mesh = M3Mesh(_geomSphere);
              mesh.subMeshes[0].mtr.diffuseTexture = texGrid2;
              rb = physicsSystem.addSphere(0.5, M3RigidBodyDesc.dynamic()..position = pos);
              break;
            case 1:
              mesh = M3Mesh(_geomCube);
              mesh.subMeshes[0].mtr.diffuseTexture = texGrid;
              rb = physicsSystem.addBox(0.5, 0.5, 0.5, M3RigidBodyDesc.dynamic()..position = pos);
              break;
            default:
              mesh = M3Mesh(_geomCylinder);
              mesh.subMeshes[0].mtr.diffuseTexture = texGrid2;
              rb = physicsSystem.addCylinder(0.5, 0.5, M3RigidBodyDesc.dynamic()..position = pos);
              break;
          }
          M3Entity entity = addMesh(mesh, pos)..color = meshColor;
          physicsSystem.attachEntity(entity, rb);
        }
      }
    }

    // sample cubemap
    skybox = M3Skybox(M3Texture.createSampleCubemap(gridCount: 11));
  }

  @override
  void update(double delta) {
    super.update(delta);

    double sec = totalTime;

    dirLight.lightViewer.setEuler(sec * pi / 18, -pi / 1.8, 0); // rotate light
    // M3Log.d('M3SampleScene', 'Light Direction: $dirLight');
  }

  @override
  void render2D() {
    super.render2D();

    // draw rectangle full-screen
    Matrix4 mat2D = Matrix4.identity();

    final sampleString = "Macbear 3D: sample scene";
    mat2D.setTranslation(Vector3(3, 3, 0));
    M3Resources.text2D.drawText(sampleString, mat2D, color: Vector4(0, 0.1, 0, 1));
    mat2D.setTranslation(Vector3(0, 1, 0));
    M3Resources.text2D.drawText(sampleString, mat2D, color: Vector4(0, 0.9, 0, 1));
  }
}

/// Massive scene with 1000 spheres and cubes.
class MassiveScene extends M3Scene {
  @override
  Future<void> load() async {
    if (isLoaded) return;
    await super.load();

    camera.setEuler(-pi / 12, -pi / 8, 0, distance: 30);

    final sphereGeom = M3Resources.unitSphere;

    for (int i = 0; i < 10; i++) {
      for (int j = 0; j < 10; j++) {
        for (int k = 0; k < 10; k++) {
          final mesh = M3Mesh(sphereGeom);
          mesh.subMeshes[0].mtr
            ..diffuse = Vector4(0.0, 1.0, 0.0, 1.0)
            ..reflection = i / 9
            ..metallic = i / 9
            ..roughness = max(j / 9, 0.05); // Avoid zero roughness for GGX

          double x = (i - 4.5) * 2;
          double y = (j - 4.5) * 2;
          double z = (k - 4.5) * 2 + 12;

          final ball = addMesh(M3Mesh(M3Resources.unitSphere), Vector3(x, y, z));
          final cube = addMesh(M3Mesh(M3Resources.unitCube), Vector3(x + 1, y + 1, z + 1));
          ball.color = Vector4(0.0, 1.0, 0.0, 1.0);
          cube.color = Vector4(0.0, 1.0, 1.0, 1.0);
        }
      }
    }

    // Add a ground plane
    final geomPlane = M3PlaneGeom(50, 50, widthSegments: 10, heightSegments: 10, uvScale: Vector2.all(10.0));
    final plane = addMesh(M3Mesh(geomPlane), Vector3(0, 0, -2));
    M3Texture texGround = M3Texture.createCheckerboard(
      size: 2,
      lightColor: Vector4(.7, 1, .5, 1),
      darkColor: Vector4(.5, 0.8, .3, 1),
    );
    plane.mesh.subMeshes[0].mtr.diffuseTexture = texGround;

    // 02: sample cubemap
    skybox = M3Skybox(M3Texture.createSampleCubemap());
  }
}
