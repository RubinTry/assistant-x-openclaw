import 'package:video_player/video_player.dart';

dynamic createVideoElement(String src) {
  final bool isNetwork = src.startsWith('http://') || src.startsWith('https://');
  final controller = isNetwork ? VideoPlayerController.networkUrl(Uri.parse(src)) : VideoPlayerController.asset(src);
  controller.setLooping(true);
  controller.setVolume(0);
  controller.initialize().then((_) {
    controller.play();
  });
  return controller;
}

void updateTextureFromVideo(dynamic gl, int target, dynamic source) {
  // On Native, we handle this through other means or it's a no-op here.
}

void videoPlay(dynamic source) {
  if (source is VideoPlayerController) {
    source.play();
  }
}

void videoPause(dynamic source) {
  if (source is VideoPlayerController) {
    source.pause();
  }
}

void videoSeekTo(dynamic source, Duration duration) {
  if (source is VideoPlayerController) {
    source.seekTo(duration);
  }
}

double videoGetDuration(dynamic source) {
  if (source is VideoPlayerController) {
    return source.value.duration.inMilliseconds / 1000.0;
  }
  return 0.0;
}

double videoGetPosition(dynamic source) {
  if (source is VideoPlayerController) {
    return source.value.position.inMilliseconds / 1000.0;
  }
  return 0.0;
}
