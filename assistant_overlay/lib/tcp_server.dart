import 'dart:convert';
import 'dart:io';

class JarvisTCPServer {
  final int port;
  ServerSocket? _server;
  Function(String)? onMessage;

  JarvisTCPServer({this.port = 17889});

  Future<void> start() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      print('TCP Server listening on port $port');
      _server!.listen(_handleClient);
    } catch (e) {
      print('Failed to start TCP server: $e');
    }
  }

  void _handleClient(Socket socket) {
    print('[TCP] Client connected');
    socket.listen(
      (data) {
        final message = utf8.decode(data, allowMalformed: true).trim();
        if (message.isNotEmpty) {
          final lines = message.split('\n');
          for (var line in lines) {
            if (line.isNotEmpty) {
              print('[TCP] Received raw: $line');
              onMessage?.call(line);
            }
          }
        }
      },
      onDone: () {
        print('[TCP] Client disconnected');
        socket.close();
      },
      onError: (e) {
        print('[TCP] Socket error: $e');
        socket.close();
      },
    );
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }
}
