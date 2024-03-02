import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Get UDP from receivers, handle GDL90
class UdpReceiver {

  late StreamController<Uint8List> _controller;
  final List<RawDatagramSocket> _sockets = [];

  void initChannel(int port, bool broadcast) async {
    RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port).then((RawDatagramSocket socket) {
      socket.broadcastEnabled = broadcast;
      socket.listen((e) {
        Datagram? dg = socket.receive();
        if (dg != null) {
          _controller.add(dg.data);
        }
      });
      return socket;
    });
    _sockets.add(socket);
  }

  StreamSubscription<Uint8List> getStream(List<int> ports, List<bool> isBroadcast) {
    _controller = StreamController<Uint8List>();
    for(int port in ports) {
      initChannel(port, isBroadcast[ports.indexOf(port)]);
    }
    return _controller.stream.listen((event) { });
  }

  void finish() {
    for(RawDatagramSocket socket in _sockets) {
      socket.close();
    }
    _controller.close();
  }
}