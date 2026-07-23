import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';

import '../util/log.dart';
import 'gltf_accessor.dart';

/// glTF 文件解析結果
class GltfDocument {
  final String name;
  final Map<String, dynamic> json;
  final Uint8List? embeddedBin;

  late final List<GltfMesh> meshes;
  late final List<GltfMaterial> materials;
  late final List<GltfTexture> textures;
  late final List<GltfImage> images;
  late final List<GltfSkin> skins;
  late final List<GltfNode> nodes;
  late final List<GltfAnimation> animations;
  late final List<int> rootNodes;

  // Runtime loaded assets
  // Use dynamic to avoid circular dependency (should be List<M3Texture>)
  List<dynamic> runtimeTextures = [];

  GltfDocument._(this.json, this.name, this.embeddedBin);

  /// 從 JSON 解析 glTF 文件
  static GltfDocument parse(Map<String, dynamic> json, String name, Uint8List? embeddedBin) {
    final doc = GltfDocument._(json, name, embeddedBin);
    doc._parseAll();
    return doc;
  }

  void _parseAll() {
    // 1. Parse Images
    final imageList = json['images'] as List<dynamic>? ?? [];
    images = imageList.map((e) => GltfImage.parse(e as Map<String, dynamic>)).toList();

    // 2. Parse Textures
    final textureList = json['textures'] as List<dynamic>? ?? [];
    textures = textureList.map((e) => GltfTexture.parse(e as Map<String, dynamic>)).toList();

    // 3. Parse Materials
    final materialList = json['materials'] as List<dynamic>? ?? [];
    materials = materialList.map((e) => GltfMaterial.parse(e as Map<String, dynamic>)).toList();

    // 5. Parse Skins
    final skinList = json['skins'] as List<dynamic>? ?? [];
    skins = skinList.map((e) => GltfSkin.parse(this, e as Map<String, dynamic>)).toList();

    // 4. Parse Nodes
    final nodeList = json['nodes'] as List<dynamic>? ?? [];
    nodes = nodeList.map((e) => GltfNode.parse(this, e as Map<String, dynamic>)).toList();

    // 5. Parse Meshes
    final meshList = json['meshes'] as List<dynamic>? ?? [];
    meshes = meshList.asMap().entries.map((entry) {
      return GltfMesh.parse(this, entry.key, entry.value as Map<String, dynamic>);
    }).toList();

    // 6. Parse Animations
    final animationList = json['animations'] as List<dynamic>? ?? [];
    animations = animationList.map((e) => GltfAnimation.parse(this, e as Map<String, dynamic>)).toList();

    // 7. Find Root Nodes
    final childSet = <int>{};
    for (final node in nodes) {
      for (final child in node.children) {
        childSet.add(child);
      }
    }
    rootNodes = [];
    for (int i = 0; i < nodes.length; i++) {
      if (!childSet.contains(i)) {
        rootNodes.add(i);
      }
    }
    M3Log.i('GltfDocument', 'Found ${rootNodes.length} root nodes: $rootNodes');
  }

  /// 取得 Accessor 資料
  Float32List getFloatAccessor(int accessorIndex) {
    return GltfAccessor.getFloatList(json, embeddedBin!, accessorIndex);
  }

  Uint16List getUint16Accessor(int accessorIndex) {
    return GltfAccessor.getUint16List(json, embeddedBin!, accessorIndex);
  }

  Uint32List getUint32Accessor(int accessorIndex) {
    return GltfAccessor.getUint32List(json, embeddedBin!, accessorIndex);
  }

  int getAccessorCount(int accessorIndex) {
    final accessor = json['accessors'][accessorIndex] as Map<String, dynamic>;
    return accessor['count'] as int;
  }

  int getAccessorComponentType(int accessorIndex) {
    final accessor = json['accessors'][accessorIndex] as Map<String, dynamic>;
    return accessor['componentType'] as int;
  }

  /// 取得 BufferView 資料 (用於圖片讀取)
  Uint8List getBufferViewData(int bufferViewIndex) {
    final bufferView = json['bufferViews'][bufferViewIndex] as Map<String, dynamic>;
    final byteOffset = bufferView['byteOffset'] as int? ?? 0;
    final byteLength = bufferView['byteLength'] as int;

    // 假設只有一個 binary buffer (GLB 標準情況)
    // 如果是 glTF 且有 external bin，需要額外處理 (這裡簡化只支援 GLB embedded bin)
    if (embeddedBin == null) {
      throw UnimplementedError('Only GLB embedded buffers are supported for now');
    }

    return embeddedBin!.sublist(byteOffset, byteOffset + byteLength);
  }
}

/// glTF Image
class GltfImage {
  final String? uri;
  final int? bufferView;
  final String? mimeType;
  final String? name;

  GltfImage({this.uri, this.bufferView, this.mimeType, this.name});

  static GltfImage parse(Map<String, dynamic> json) {
    return GltfImage(
      uri: json['uri'] as String?,
      bufferView: json['bufferView'] as int?,
      mimeType: json['mimeType'] as String?,
      name: json['name'] as String?,
    );
  }
}

/// glTF Texture
class GltfTexture {
  final int? sampler;
  final int? source; // index of images
  final String? name;

  GltfTexture({this.sampler, this.source, this.name});

  static GltfTexture parse(Map<String, dynamic> json) {
    return GltfTexture(sampler: json['sampler'] as int?, source: json['source'] as int?, name: json['name'] as String?);
  }
}

/// glTF Material
class GltfMaterial {
  final String name;
  final Vector4 baseColorFactor;
  final int? baseColorTextureIndex; // index of textures
  final double metallicFactor;
  final double roughnessFactor;
  final String alphaMode; // "OPAQUE", "MASK", "BLEND"
  final double alphaCutoff;

  GltfMaterial({
    required this.name,
    required this.baseColorFactor,
    this.baseColorTextureIndex,
    this.metallicFactor = 1.0,
    this.roughnessFactor = 1.0,
    this.alphaMode = 'OPAQUE',
    this.alphaCutoff = 0.5,
  });

  static GltfMaterial parse(Map<String, dynamic> json) {
    final pbr = json['pbrMetallicRoughness'] as Map<String, dynamic>? ?? {};

    // Base Color Factor
    Vector4 color = Vector4(1.0, 1.0, 1.0, 1.0);
    if (pbr.containsKey('baseColorFactor')) {
      final list = (pbr['baseColorFactor'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
      if (list.length == 4) {
        color = Vector4(list[0], list[1], list[2], list[3]);
      }
    }

    // Base Color Texture
    int? texIndex;
    if (pbr.containsKey('baseColorTexture')) {
      final tex = pbr['baseColorTexture'] as Map<String, dynamic>;
      texIndex = tex['index'] as int?;
    }

    // Metallic/Roughness
    double metallic = 1.0;
    double roughness = 1.0;
    if (pbr.containsKey('metallicFactor')) {
      metallic = (pbr['metallicFactor'] as num).toDouble();
    }
    if (pbr.containsKey('roughnessFactor')) {
      roughness = (pbr['roughnessFactor'] as num).toDouble();
    }

    return GltfMaterial(
      name: json['name'] as String? ?? 'Material',
      baseColorFactor: color,
      baseColorTextureIndex: texIndex,
      metallicFactor: metallic,
      roughnessFactor: roughness,
      alphaMode: json['alphaMode'] as String? ?? 'OPAQUE',
      alphaCutoff: (json['alphaCutoff'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// glTF Skin
class GltfSkin {
  final GltfDocument document;
  final String name;
  final int? inverseBindMatricesAccessor;
  final List<int> joints;

  GltfSkin({required this.document, required this.name, this.inverseBindMatricesAccessor, required this.joints});

  static GltfSkin parse(GltfDocument doc, Map<String, dynamic> json) {
    return GltfSkin(
      document: doc,
      name: json['name'] as String? ?? 'Skin',
      inverseBindMatricesAccessor: json['inverseBindMatrices'] as int?,
      joints: (json['joints'] as List<dynamic>).map((e) => e as int).toList(),
    );
  }

  Float32List? getInverseBindMatrices() {
    if (inverseBindMatricesAccessor == null) return null;
    return document.getFloatAccessor(inverseBindMatricesAccessor!);
  }
}

/// glTF Mesh
class GltfMesh {
  final GltfDocument document;
  final int index;
  final String name;
  final List<GltfPrimitive> primitives;

  GltfMesh._(this.document, this.index, this.name, this.primitives);

  static GltfMesh parse(GltfDocument doc, int index, Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'Mesh_$index';
    final primList = json['primitives'] as List<dynamic>? ?? [];
    final primitives = primList.asMap().entries.map((entry) {
      return GltfPrimitive.parse(doc, entry.value as Map<String, dynamic>);
    }).toList();
    return GltfMesh._(doc, index, name, primitives);
  }
}

/// glTF Primitive (一個 Mesh 可能有多個 Primitive)
class GltfPrimitive {
  final GltfDocument document;

  // Accessor indices
  final int? positionAccessor;
  final int? normalAccessor;
  final int? texCoordAccessor;
  final int? jointAccessor;
  final int? weightAccessor;
  final int? indicesAccessor;

  // Primitive mode (4 = TRIANGLES)
  final int mode;

  // Material index
  final int? materialIndex;

  // Skin index
  final int? skinIndex;

  GltfPrimitive._({
    required this.document,
    this.positionAccessor,
    this.normalAccessor,
    this.texCoordAccessor,
    this.jointAccessor,
    this.weightAccessor,
    this.indicesAccessor,
    this.mode = 4,
    this.materialIndex,
    this.skinIndex,
  });

  static GltfPrimitive parse(GltfDocument doc, Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? {};

    return GltfPrimitive._(
      document: doc,
      positionAccessor: attributes['POSITION'] as int?,
      normalAccessor: attributes['NORMAL'] as int?,
      texCoordAccessor: attributes['TEXCOORD_0'] as int?,
      jointAccessor: attributes['JOINTS_0'] as int?,
      weightAccessor: attributes['WEIGHTS_0'] as int?,
      indicesAccessor: json['indices'] as int?,
      mode: json['mode'] as int? ?? 4,
      materialIndex: json['material'] as int?, // index into doc.materials
      skinIndex: json['skin'] as int?, // optional skin index
    );
  }

  /// 取得頂點位置資料
  Float32List? getPositions() {
    if (positionAccessor == null) return null;
    return document.getFloatAccessor(positionAccessor!);
  }

  /// 取得法向量資料
  Float32List? getNormals() {
    if (normalAccessor == null) return null;
    return document.getFloatAccessor(normalAccessor!);
  }

  /// 取得 UV 座標資料
  Float32List? getTexCoords() {
    if (texCoordAccessor == null) return null;
    return document.getFloatAccessor(texCoordAccessor!);
  }

  /// 取得骨骼索引資料
  Uint16List? getJoints() {
    if (jointAccessor == null) return null;
    return document.getUint16Accessor(jointAccessor!);
  }

  /// 取得骨骼權重資料
  Float32List? getWeights() {
    if (weightAccessor == null) return null;
    return document.getFloatAccessor(weightAccessor!);
  }

  /// 取得索引資料 (自動處理 UNSIGNED_SHORT/UNSIGNED_INT)
  List<int>? getIndices() {
    if (indicesAccessor == null) return null;
    final componentType = document.getAccessorComponentType(indicesAccessor!);
    if (componentType == GltfAccessor.UNSIGNED_SHORT) {
      // UNSIGNED_SHORT
      return document.getUint16Accessor(indicesAccessor!).toList();
    } else if (componentType == GltfAccessor.UNSIGNED_INT) {
      // UNSIGNED_INT
      return document.getUint32Accessor(indicesAccessor!).toList();
    }
    return null;
  }

  /// 取得頂點數量
  int get vertexCount {
    if (positionAccessor == null) return 0;
    return document.getAccessorCount(positionAccessor!);
  }
}

/// glTF Node
class GltfNode {
  final GltfDocument document;
  final String name;
  final int? meshIndex;
  final int? skinIndex;
  final List<int> children;

  // Transform (mutable for animation)
  Vector3 translation;
  Quaternion rotation;
  Vector3 scale;
  final Matrix4? matrix;

  /// Computed world matrix for this node.
  Matrix4 worldMatrix = Matrix4.identity();

  GltfNode({
    required this.document,
    required this.name,
    this.meshIndex,
    this.skinIndex,
    this.children = const [],
    required this.translation,
    required this.rotation,
    required this.scale,
    this.matrix,
  });

  static GltfNode parse(GltfDocument doc, Map<String, dynamic> json) {
    Vector3? t;
    if (json.containsKey('translation')) {
      final l = (json['translation'] as List).cast<num>();
      t = Vector3(l[0].toDouble(), l[1].toDouble(), l[2].toDouble());
    }

    Quaternion? r;
    if (json.containsKey('rotation')) {
      final l = (json['rotation'] as List).cast<num>();
      r = Quaternion(l[0].toDouble(), l[1].toDouble(), l[2].toDouble(), l[3].toDouble());
    }

    Vector3? s;
    if (json.containsKey('scale')) {
      final l = (json['scale'] as List).cast<num>();
      s = Vector3(l[0].toDouble(), l[1].toDouble(), l[2].toDouble());
    }

    Matrix4? m;
    if (json.containsKey('matrix')) {
      final l = (json['matrix'] as List).cast<num>();
      m = Matrix4.fromList(l.map((e) => e.toDouble()).toList());
    }

    return GltfNode(
      document: doc,
      name: json['name'] as String? ?? 'Node',
      meshIndex: json['mesh'] as int?,
      skinIndex: json['skin'] as int?,
      children: (json['children'] as List?)?.cast<int>() ?? [],
      translation: t ?? Vector3.zero(),
      rotation: r ?? Quaternion.identity(),
      scale: s ?? Vector3.all(1.0),
      matrix: m,
    );
  }

  /// Computes the world matrix for this node and its children.
  void computeWorldMatrix(Matrix4 parentMatrix, [List<GltfNode>? nodes]) {
    final nodeList = nodes ?? document.nodes;
    if (matrix != null) {
      worldMatrix.setFrom(parentMatrix * matrix!);
    } else {
      worldMatrix.setFrom(parentMatrix * Matrix4.compose(translation, rotation, scale));
    }

    for (final childIndex in children) {
      nodeList[childIndex].computeWorldMatrix(worldMatrix, nodeList);
    }
  }

  /// Copies all properties from another node.
  void setFrom(GltfNode other) {
    translation.setFrom(other.translation);
    rotation.setFrom(other.rotation);
    scale.setFrom(other.scale);
    if (matrix != null && other.matrix != null) {
      matrix!.setFrom(other.matrix!);
    }
    worldMatrix.setFrom(other.worldMatrix);
  }

  /// Creates a copy of this node for instance-sharing.
  /// Note: This does not recursively clone children since nodes are often
  /// referenced by index in the document. Hierarchy cloning is handled higher up.
  GltfNode clone() {
    return GltfNode(
      document: document,
      name: name,
      meshIndex: meshIndex,
      skinIndex: skinIndex,
      children: List.from(children),
      translation: translation.clone(),
      rotation: rotation.clone(),
      scale: scale.clone(),
      matrix: matrix?.clone(),
    )..setFrom(this);
  }
}

/// glTF Animation
class GltfAnimation {
  final GltfDocument document;
  final String name;
  final List<GltfAnimationChannel> channels;
  final List<GltfAnimationSampler> samplers;

  GltfAnimation({required this.document, required this.name, required this.channels, required this.samplers});

  static GltfAnimation parse(GltfDocument doc, Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'Animation';

    final samplerList = json['samplers'] as List<dynamic>? ?? [];
    final samplers = samplerList.map((e) => GltfAnimationSampler.parse(doc, e as Map<String, dynamic>)).toList();

    final channelList = json['channels'] as List<dynamic>? ?? [];
    final channels = channelList.map((e) => GltfAnimationChannel.parse(doc, e as Map<String, dynamic>)).toList();

    return GltfAnimation(document: doc, name: name, channels: channels, samplers: samplers);
  }
}

/// glTF Animation Channel
class GltfAnimationChannel {
  final GltfDocument document;
  final int samplerIndex;
  final int? targetNodeIndex;
  final String targetPath; // "translation", "rotation", "scale", "weights"

  GltfAnimationChannel({
    required this.document,
    required this.samplerIndex,
    this.targetNodeIndex,
    required this.targetPath,
  });

  static GltfAnimationChannel parse(GltfDocument doc, Map<String, dynamic> json) {
    final target = json['target'] as Map<String, dynamic>;
    return GltfAnimationChannel(
      document: doc,
      samplerIndex: json['sampler'] as int,
      targetNodeIndex: target['node'] as int?,
      targetPath: target['path'] as String,
    );
  }
}

/// glTF Animation Sampler
class GltfAnimationSampler {
  final GltfDocument document;
  final int inputAccessor; // time
  final int outputAccessor; // values (TRS)
  final String interpolation; // "LINEAR", "STEP", "CUBICSPLINE"

  GltfAnimationSampler({
    required this.document,
    required this.inputAccessor,
    required this.outputAccessor,
    required this.interpolation,
  });

  static GltfAnimationSampler parse(GltfDocument doc, Map<String, dynamic> json) {
    return GltfAnimationSampler(
      document: doc,
      inputAccessor: json['input'] as int,
      outputAccessor: json['output'] as int,
      interpolation: json['interpolation'] as String? ?? 'LINEAR',
    );
  }

  Float32List getInputs() => document.getFloatAccessor(inputAccessor);
  Float32List getOutputs() => document.getFloatAccessor(outputAccessor);
}
