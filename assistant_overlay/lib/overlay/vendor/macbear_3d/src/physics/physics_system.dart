import '../m3_internal.dart';

/// Physics-entity binding layer.
class M3PhysicsSystem {
  final M3PhysicsEngine _engine;

  // update per step
  double _accumulator = 0.0;
  final double _timeStep = 1 / 60.0;
  final int _maxStepsPerFrame = 6;

  double get _interpolationAlpha {
    return _accumulator / _timeStep;
  }

  // 綁定：RigidBody → Entity
  final Map<int, M3Entity> _bodyToEntity = {};

  /// constructor
  M3PhysicsSystem(this._engine);

  M3PhysicsEngine get engine => _engine;
  String get info {
    return _engine.info;
  }

  Future<void> init({Vector3? gravity}) async {
    await _engine.init(gravity: gravity);
  }

  /// dispose physics system
  void dispose() {
    _engine.dispose();
    _bodyToEntity.clear();
  }

  /// reset physics system
  void reset() {
    _engine.resetWorld();
    _bodyToEntity.clear();
    _accumulator = 0.0;
  }

  M3RigidBody addBox(double hx, double hy, double hz, M3RigidBodyDesc? desc) {
    final body = _engine.createRigidBody(desc ?? M3RigidBodyDesc.dynamic());
    _engine.createCollider(body, M3ColliderDesc.cuboid(hx, hy, hz));
    return body;
  }

  M3RigidBody addSphere(double radius, M3RigidBodyDesc? desc) {
    final body = _engine.createRigidBody(desc ?? M3RigidBodyDesc.dynamic());
    _engine.createCollider(body, M3ColliderDesc.ball(radius));
    return body;
  }

  M3RigidBody addCylinder(double radius, double halfHeight, M3RigidBodyDesc? desc) {
    final body = _engine.createRigidBody(desc ?? M3RigidBodyDesc.dynamic());
    _engine.createCollider(body, M3ColliderDesc.cylinder(radius, halfHeight));
    return body;
  }

  M3RigidBody addCapsule(double radius, double halfHeight, M3RigidBodyDesc? desc) {
    final body = _engine.createRigidBody(desc ?? M3RigidBodyDesc.dynamic());
    _engine.createCollider(body, M3ColliderDesc.capsule(radius, halfHeight));
    return body;
  }

  void attachEntity(M3Entity entity, M3RigidBody body) {
    entity.rigidBody = body;
    _bodyToEntity[body.handle] = entity;
  }

  void detachEntity(M3Entity entity) {
    final body = entity.rigidBody;
    if (body != null) {
      _bodyToEntity.remove(body.handle);
      entity.rigidBody = null;
    }
  }

  /// update physics world
  void update(double dt, {void Function()? onBeforeStep}) {
    _accumulator += dt;
    int steps = 0;
    while (_accumulator >= _timeStep && steps < _maxStepsPerFrame) {
      if (onBeforeStep != null) onBeforeStep();
      _engine.step(_timeStep);
      _accumulator -= _timeStep;
      steps++;
    }

    // sync physics to entities
    _syncToEntities();
  }

  // sync from physics system to entities
  void _syncToEntities() {
    for (final entity in _bodyToEntity.values) {
      entity.syncFromPhysics(_interpolationAlpha);
    }
  }
}
