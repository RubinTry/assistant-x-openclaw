// ignore_for_file: unused_import
// Macbear3D engine
import '../m3_internal.dart';

import '../shaders_gen/Mirror.es3.frag.g.dart';
import '../shaders_gen/Mirror.es3.vert.g.dart';
import '../shaders_gen/Rect.es3.frag.g.dart';
import '../shaders_gen/Rect.es3.vert.g.dart';
import '../shaders_gen/Simple.es3.frag.g.dart';
import '../shaders_gen/Simple.es3.vert.g.dart';
import '../shaders_gen/SimpleLighting.es3.vert.g.dart';
import '../shaders_gen/Skybox.es3.frag.g.dart';
import '../shaders_gen/Skybox.es3.vert.g.dart';
import '../shaders_gen/SkyboxReflect.es3.vert.g.dart';
import '../shaders_gen/TexturedLighting.es3.frag.g.dart';
import '../shaders_gen/TexturedLighting.es3.vert.g.dart';
import '../shaders_gen/Unlit.es3.frag.g.dart';
import '../shaders_gen/Unlit.es3.vert.g.dart';
import '../shaders_gen/Water.es3.frag.g.dart';
import '../shaders_gen/Water.es3.vert.g.dart';
// GLSL functions include
import '../shaders_gen/glsl/FogFS.es3.glsl.g.dart';
import '../shaders_gen/glsl/LightFS.es3.glsl.g.dart';
import '../shaders_gen/glsl/PixelFS.es3.glsl.g.dart';
import '../shaders_gen/glsl/ShadowFS.es3.glsl.g.dart';
import '../shaders_gen/glsl/ShadowVS.es3.glsl.g.dart';
import '../shaders_gen/glsl/SkinningVS.es3.glsl.g.dart';

class M3Resources {
  // ------------------------------
  // Textures
  // ------------------------------
  static final texWhite = M3Texture.createSolidColor(Vector4(1, 1, 1, 1));
  static final texNormal = M3Texture.createSolidColor(Vector4(0.5, 0.5, 1, 1));
  static final texDefaultCube = M3Texture.createDefaultIBLCube();

  // axis gizmo mesh
  static M3Mesh? _axisDotMesh;
  static M3Mesh? _axisGizmoMesh;
  static M3Mesh? _frustumMesh;
  static M3Mesh get axisDotMesh => _axisDotMesh ??= M3MeshFactory.createAxisDot();
  static M3Mesh get axisGizmoMesh => _axisGizmoMesh ??= M3MeshFactory.createAxisGizmo();
  static M3Mesh get frustumMesh => _frustumMesh ??= M3MeshFactory.createFrustum();

  // ------------------------------
  // Camera: debug
  // ------------------------------
  static M3Camera? debugCamera;

  // ------------------------------
  // Geometries: debug
  // ------------------------------
  static final debugAxis = M3DebugAxisGeom(size: 0.5);
  static final debugPointLight = M3SphereGeom(1.0, widthSegments: 8, heightSegments: 4);
  static final debugSphere = M3DebugSphereGeom(radius: 1.0);
  static final debugFrustum = M3BoxGeom(2.0, 2.0, 2.0);
  static final debugDot = M3OctahedralGeom(0.25);
  static final debugView = M3PlaneGeom(1.8, 1.8, widthSegments: 6, heightSegments: 4);

  // ------------------------------
  // Unit geometries
  // ------------------------------
  static final unitCube = M3BoxGeom(1.0, 1.0, 1.0);
  static final unitCylinder = M3CylinderGeom(0.5, 0.5, 1.0);
  static final unitBone = M3OctahedralGeom(0.5, bias: Vector3(-0.6, 0, 0));
  static final unitOctahedral = M3OctahedralGeom(0.5);
  static final unitSphere = M3SphereGeom(0.5);

  // ------------------------------
  // 2D shapes
  // ------------------------------
  // for dynamic draw: line, triangle
  static M3Shape2D? _line;
  static M3Shape2D? _triangle;

  // text2D from sprite, rectUnit for image
  static M3Text2D? _text2D;
  static M3Rectangle2D? _rectUnit;

  static M3Text2D get text2D {
    return _text2D!;
  }

  static M3Shape2D get line {
    _line ??= M3Shape2D(WebGL.LINES, 2)..createVBO(WebGL.DYNAMIC_DRAW);
    return _line!;
  }

  static M3Shape2D get triangle {
    _triangle ??= M3Shape2D(WebGL.TRIANGLES, 3)..createVBO(WebGL.DYNAMIC_DRAW);
    return _triangle!;
  }

  static M3Rectangle2D get rectUnit {
    _rectUnit ??= M3Rectangle2D()
      ..setRectangle(0, 0, 1, 1)
      ..createVBO(WebGL.STATIC_DRAW);
    return _rectUnit!;
  }

  // ------------------------------
  // Programs
  // ------------------------------
  static M3Program? programSimple;
  static M3Program? programSkybox;
  static M3Program? programRectangle;
  static M3Program? programMirror; // plane reflection (mirror / water)
  static M3ProgramWater? programWater; // water no shadow
  static M3ProgramWaterCSM? programWaterCSM; // water shadow CSM
  static M3ProgramEye? programSkyboxReflect;
  static M3Program? programExternalOES; // external texture: video streaming
  // with lighting
  static M3ProgramLighting? programSimpleLighting;
  static M3ProgramLighting? programTexture;
  static M3ProgramShadowmap? programShadowmap;
  static M3ProgramShadowCSM? programShadowCSM;

  // ignore: non_constant_identifier_names
  static final _SkinNormalVS_glsl = "#define ENABLE_NORMAL \n$SkinningVS_glsl";

  static Future<void> init() async {
    M3Log.i('M3Resources', 'init starting...');
    // Textures
    texWhite;
    texNormal;
    texDefaultCube;
    M3Log.i('M3Resources', 'basic textures initialized');

    // debug camera for directional-light shadow map frustum only
    debugCamera = M3Camera(); // remark to disable debug camera
    debugCamera
      ?..setViewport(0, 0, 8, 5, fovy: 45, near: 1, far: 30)
      ..target.setFrom(Vector3(-10, 0, 1))
      ..setEuler(0, -pi / 5, 0, distance: 4);

    // Mesh
    axisDotMesh;
    axisGizmoMesh;
    frustumMesh;

    // Geometries
    debugAxis;
    debugPointLight;
    debugSphere;
    debugFrustum;
    debugDot;
    debugView;

    unitCube;
    unitCylinder;
    unitBone;
    unitOctahedral;
    unitSphere;
    M3Log.i('M3Resources', 'unit geometries initialized');

    // 2D
    line;
    triangle;
    rectUnit;
    _text2D = await M3Text2D.createText2D(fontSize: 30);
    M3Log.i('M3Resources', 'text2D initialized');

    // Programs
    M3Log.i('M3Resources', 'initializing shader programs...');
    programSimple = M3Program(SkinningVS_glsl + Simple_vert, Simple_frag);
    programSkybox = M3Program(Skybox_vert, Skybox_frag);
    programRectangle = M3Program(Rect_vert, Rect_frag);
    programSkyboxReflect = M3ProgramEye(
      _SkinNormalVS_glsl + SkyboxReflect_vert,
      Skybox_frag,
      reflectionType: M3ReflectionType.cubemap,
    );
    programSimpleLighting = M3ProgramLighting(_SkinNormalVS_glsl + SimpleLighting_vert, Simple_frag);

    // plane reflection (mirror / water)
    // programMirror = M3Program(Mirror_vert, Mirror_frag);
    programMirror = M3Program(SkinningVS_glsl + Simple_vert, Mirror_frag, reflectionType: M3ReflectionType.planar);

    // external texture: video streaming
    String fsUnlit = Unlit_frag;
    if (PlatformInfo.isIOS || PlatformInfo.isMacOS) {
      // iOS, macOS: format BGRA
      // fsUnlit = '#define ENABLE_TEXTURE0_BGRA \n$fsUnlit';

      // Android: external OES unable to use SurfaceTexture
      // ANGLE use libEGL_angle.so, Android use libEGL.so
      // so discard to use external OES
      /* String fsExternalOES = '''
#extension GL_OES_EGL_image_external_essl3 : require
#define ENABLE_EXTERNAL_OES
'''; */
    }
    programExternalOES = M3Program(Unlit_vert, fsUnlit);

    // lighting related programs
    setLightingProgram(M3ShaderOptions());

    M3Log.i('M3Resources', 'init done');
  }

  static void setLightingProgram(M3ShaderOptions options) {
    programTexture?.dispose();
    programShadowmap?.dispose();
    programShadowCSM?.dispose();

    // texture lighting program
    String strVert = _SkinNormalVS_glsl + TexturedLighting_vert;
    String strFrag = TexturedLighting_frag;

    // pixel lighting: phong shading, cartoon, PBR, IBL
    if (options.perPixel) {
      if (options.pbr) {
        // ES3 PBR: Use modern ES3 shaders
        strVert = "#define ENABLE_PBR \n$strVert";
        strFrag = "#define ENABLE_PBR \n$strFrag";
        if (options.ibl) {
          strFrag = "#define ENABLE_IBL \n$strFrag";
        }
      } else {
        // ES2 Lighting: phong shading, cartoon
        if (options.cartoon) {
          strFrag = "#define ENABLE_CARTOON \n$strFrag";
        }
      }
      // add pixel lighting shader to vertex/fragment shader for final result
      strVert = "#define ENABLE_PIXEL_LIGHTING \n$strVert";
      strFrag = "#define ENABLE_PIXEL_LIGHTING \n$strFrag";
      strFrag = strFrag + LightFS_glsl + PixelFS_glsl;
    }

    if (options.fog) {
      strVert = "#define ENABLE_FOG \n$strVert";
      strFrag = "#define ENABLE_FOG \n$strFrag \n$FogFS_glsl";
    }

    M3Log.i('setLightingProgram', 'prepare lighting');
    programTexture = M3ProgramLighting(strVert, strFrag);

    // shadow map, CSM, PCF
    String strShadowFS = ShadowFS_glsl;

    // PCF - 0:none, 1:default(4-tap), 2:3x3, 3:5x5
    if (options.pcf == 1) {
      strShadowFS = "#define ENABLE_PCF \n$strShadowFS";
    } else if (options.pcf == 2) {
      strShadowFS = "#define ENABLE_PCF_3x3 \n$strShadowFS";
    } else if (options.pcf == 3) {
      strShadowFS = "#define ENABLE_PCF_5x5 \n$strShadowFS";
    }

    strVert = ShadowVS_glsl + strVert; // shadow vertex shader
    strFrag = strShadowFS + strFrag; // shadow fragment shader

    // shadow map program
    String vsShadow = "#define ENABLE_SHADOW_MAP \n$strVert";
    String fsShadow = "#define ENABLE_SHADOW_MAP \n$strFrag";
    programShadowmap = M3ProgramShadowmap(vsShadow, fsShadow);

    // shadow CSM program
    vsShadow = "#define ENABLE_SHADOW_CSM \n$strVert";
    fsShadow = "#define ENABLE_SHADOW_CSM \n$strFrag";
    programShadowCSM = M3ProgramShadowCSM(vsShadow, fsShadow);

    // water program without shadow
    String vsWater = SkinningVS_glsl + Water_vert;
    String fsWater = Water_frag + LightFS_glsl;
    // bool bSpecularLight = false;
    // if (bSpecularLight) {
    //   fsWater = "#define ENABLE_WATER_SPECULAR \n$fsWater";
    // }
    if (options.fog) {
      vsWater = "#define ENABLE_FOG \n$vsWater";
      fsWater = "#define ENABLE_FOG \n$fsWater \n$FogFS_glsl";
    }
    programWater = M3ProgramWater(vsWater, fsWater);

    // water program with shadow CSM
    vsWater = "#define ENABLE_SHADOW_CSM \n$ShadowVS_glsl \n$vsWater";
    fsWater = "#define ENABLE_SHADOW_CSM \n$strShadowFS \n$fsWater";
    programWaterCSM = M3ProgramWaterCSM(vsWater, fsWater);
  }

  static void checkUpdate(M3ShaderOptions options) {
    if (options.isDirty) {
      setLightingProgram(options);
      options.isDirty = false;
    }
  }

  static void dispose() {
    // Textures
    texWhite.dispose();
    texNormal.dispose();
    texDefaultCube.dispose();

    // Geometries
    debugAxis.dispose();
    debugPointLight.dispose();
    debugSphere.dispose();
    debugFrustum.dispose();
    debugDot.dispose();
    debugView.dispose();

    unitCube.dispose();
    unitBone.dispose();
    unitOctahedral.dispose();
    unitSphere.dispose();

    // 2D
    _line?.dispose();
    _triangle?.dispose();
    _rectUnit?.dispose();
    _text2D?.dispose();

    // Programs
    programSimple?.dispose();
    programSkybox?.dispose();
    programRectangle?.dispose();
    programMirror?.dispose();
    programWater?.dispose();
    programWaterCSM?.dispose();
    programSkyboxReflect?.dispose();
    programExternalOES?.dispose();
    programSimpleLighting?.dispose();

    programTexture?.dispose();
    programShadowmap?.dispose();
    programShadowCSM?.dispose();
  }
}
