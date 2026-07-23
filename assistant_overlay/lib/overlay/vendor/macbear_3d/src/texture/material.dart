// Macbear3D engine
import '../m3_internal.dart';
import '../gltf/gltf_parser.dart';

/// Alpha blending modes for materials.
enum M3AlphaMode {
  /// Standard opaque rendering.
  opaque,

  /// Semi-transparent rendering with alpha blending.
  blend,

  /// Binary transparency (pixel is either visible or discarded).
  mask,
}

/// Material properties for rendering (diffuse color, specular, shininess, textures).
class M3Material {
  Vector4 diffuse = Vector4(1.0, 1.0, 1.0, 1.0);
  Vector3 specular = Vector3(0.3, 0.3, 0.3);
  double shininess = 16; // glossiness [1 ~ 128]
  double reflection = 0.0;
  double metallic = 0.0;
  double roughness = 0.8;
  int mipLevel = 7; // max mipmap level for reflection roughness
  M3AlphaMode alphaMode = M3AlphaMode.opaque;
  int renderOrder = 0; // manual override for fine-tuned sorting

  // textures
  M3Texture diffuseTexture = M3Resources.texWhite;
  Matrix3 texMatrix = Matrix3.identity();

  M3PlanarReflection? planarReflection; // planar reflection

  M3Material();

  /// Sets the material to a matte (diffuse-only) state.
  /// No reflection, no specular highlights, and full roughness.
  void setMatte() {
    metallic = 0.0;
    roughness = 1.0;
    reflection = 0.0;
    specular.setZero();
    shininess = 1.0;
  }

  /// Sets the material to a glossy (reflective) state.
  void setGlossy() {
    metallic = 1.0;
    roughness = 0.0;
    reflection = 1.0;
    specular.setValues(1.0, 1.0, 1.0);
    shininess = 128.0;
  }

  /// Creates a deep copy of this material.
  /// Vector and Matrix properties are cloned, while texture references are shared.
  M3Material clone() {
    return M3Material()..setFrom(this);
  }

  /// Copies all properties from another material.
  void setFrom(M3Material other) {
    diffuse.setFrom(other.diffuse);
    specular.setFrom(other.specular);
    shininess = other.shininess;
    reflection = other.reflection;
    metallic = other.metallic;
    roughness = other.roughness;
    mipLevel = other.mipLevel;
    alphaMode = other.alphaMode;
    renderOrder = other.renderOrder;
    diffuseTexture = other.diffuseTexture;
    texMatrix.setFrom(other.texMatrix);
    planarReflection = other.planarReflection;
  }

  factory M3Material.fromGltf(GltfMaterial gltfMat, GltfDocument doc) {
    final mtr = M3Material();
    // Base Color
    mtr.diffuse.setFrom(gltfMat.baseColorFactor);
    mtr.metallic = gltfMat.metallicFactor;
    mtr.roughness = gltfMat.roughnessFactor;
    if (gltfMat.alphaMode == 'BLEND') {
      mtr.alphaMode = M3AlphaMode.blend;
    } else if (gltfMat.alphaMode == 'MASK') {
      mtr.alphaMode = M3AlphaMode.mask;
    }

    // Base Color Texture
    if (gltfMat.baseColorTextureIndex != null) {
      final texIndex = gltfMat.baseColorTextureIndex!;
      if (texIndex < doc.runtimeTextures.length) {
        final tex = doc.runtimeTextures[texIndex];
        if (tex is M3Texture) {
          mtr.diffuseTexture = tex;
        }
      }
    }
    return mtr;
  }
}
