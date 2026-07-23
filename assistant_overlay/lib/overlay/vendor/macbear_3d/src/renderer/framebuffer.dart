import 'dart:typed_data';

// Macbear3D engine
import '../m3_internal.dart';

/// A WebGL framebuffer object for off-screen rendering (e.g., shadow maps).
///
/// Creates and manages a depth texture attached to a framebuffer.
class M3Framebuffer {
  RenderingContext get gl => M3AppEngine.instance.renderEngine.gl;

  int frameW = 1024;
  int frameH = 1024;

  late Framebuffer _fbo;
  Renderbuffer? _depthRenderbuffer;
  M3Texture? _colorTexture;
  M3Texture? _depthTexture;

  M3Texture get depthTexture => _depthTexture!;
  M3Texture get colorTexture => _colorTexture!;

  M3Framebuffer(this.frameW, this.frameH) {
    // Create FBO
    _fbo = gl.createFramebuffer();
    gl.bindFramebuffer(WebGL.FRAMEBUFFER, _fbo);
  }

  /// Create color texture
  M3Texture? createColorTexture({int target = WebGL.TEXTURE_2D}) {
    M3Texture? tex;
    int texTarget = WebGL.TEXTURE_2D;
    if (target == WebGL.TEXTURE_CUBE_MAP) {
      tex = M3Texture.createEmptyCubemap(frameW);
      texTarget = WebGL.TEXTURE_CUBE_MAP_POSITIVE_X;
    } else if (target == WebGL.TEXTURE_2D) {
      tex = M3Texture.createEmpty2D(frameW, frameH, wrap: WebGL.CLAMP_TO_EDGE);
    } else {
      assert(false, "Unsupported target: $target");
    }
    tex?.attachToFramebuffer(WebGL.COLOR_ATTACHMENT0, texTarget);

    _colorTexture = tex;
    _checkStatus();
    return tex;
  }

  /// Create depth texture
  /// internal format: DEPTH_COMPONENT16, (DEPTH_COMPONENT24), DEPTH_COMPONENT32F
  /// with stencil format: DEPTH24_STENCIL8
  M3Texture createDepthTexture({int depthFormat = WebGL.DEPTH_COMPONENT24}) {
    M3Texture tex = M3Texture(useMipmaps: false, wrap: WebGL.CLAMP_TO_EDGE)
      ..name = 'depth'
      ..texW = frameW
      ..texH = frameH;

    // depthFormat → pixel type mapping
    final pixelType = switch (depthFormat) {
      WebGL.DEPTH_COMPONENT32F => WebGL.FLOAT,
      WebGL.DEPTH_COMPONENT16 => WebGL.UNSIGNED_SHORT,
      _ => WebGL.UNSIGNED_INT, // DEPTH_COMPONENT24, DEPTH24_STENCIL8
    };

    // depth-Z compare mode
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_COMPARE_MODE, WebGL.COMPARE_REF_TO_TEXTURE);
    gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_COMPARE_FUNC, WebGL.LESS);

    gl.texImage2D(WebGL.TEXTURE_2D, 0, depthFormat, frameW, frameH, 0, WebGL.DEPTH_COMPONENT, pixelType, null);

    final attachment = switch (depthFormat) {
      WebGL.DEPTH24_STENCIL8 => WebGL.DEPTH_STENCIL_ATTACHMENT,
      _ => WebGL.DEPTH_ATTACHMENT,
    };
    tex.attachToFramebuffer(attachment, WebGL.TEXTURE_2D);

    _depthTexture = tex;
    _checkStatus();
    return tex;
  }

  /// Create depth renderbuffer: DEPTH_COMPONENT24, (DEPTH24_STENCIL8)
  void createDepthRenderbuffer({int depthFormat = WebGL.DEPTH24_STENCIL8}) {
    _depthRenderbuffer = gl.createRenderbuffer();
    gl.bindRenderbuffer(WebGL.RENDERBUFFER, _depthRenderbuffer!);
    gl.renderbufferStorage(WebGL.RENDERBUFFER, depthFormat, frameW, frameH);

    final attachment = switch (depthFormat) {
      WebGL.DEPTH24_STENCIL8 => WebGL.DEPTH_STENCIL_ATTACHMENT,
      _ => WebGL.DEPTH_ATTACHMENT,
    };
    gl.framebufferRenderbuffer(WebGL.FRAMEBUFFER, attachment, WebGL.RENDERBUFFER, _depthRenderbuffer!);

    _checkStatus();
  }

  void _checkStatus() {
    assert(() {
      final status = gl.checkFramebufferStatus(WebGL.FRAMEBUFFER);
      if (status != WebGL.FRAMEBUFFER_COMPLETE) {
        String msg = 'n/a';
        switch (status) {
          case WebGL.FRAMEBUFFER_INCOMPLETE_ATTACHMENT:
            msg = 'missing attachment';
            break;
          case WebGL.FRAMEBUFFER_INCOMPLETE_DIMENSIONS:
            msg = 'incomplete dimensions';
            break;
          case WebGL.FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT:
            msg = 'incomplete missing attachment';
            break;
          case WebGL.FRAMEBUFFER_UNSUPPORTED:
            msg = 'unsupported';
            break;
          default:
            msg = '0x${status.toRadixString(16).toUpperCase()} unknown';
            break;
        }
        M3Log.e('Framebuffer', 'FBO error: $msg');
      }

      return true;
    }());
  }

  /// Bind this FBO and set viewport size
  void bind() {
    gl.bindFramebuffer(WebGL.FRAMEBUFFER, _fbo);
    gl.viewport(0, 0, frameW, frameH);

    if (_colorTexture == null) {
      gl.drawBuffers(Uint32List.fromList([WebGL.NONE]));
    }
    _checkStatus();
  }

  void dispose() {
    _colorTexture?.dispose();
    _depthTexture?.dispose();
    if (_depthRenderbuffer != null) gl.deleteRenderbuffer(_depthRenderbuffer!);
    gl.deleteFramebuffer(_fbo);
  }
}
