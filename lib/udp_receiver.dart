import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Get UDP from receivers, handle GDL90
class UdpReceiver {

  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

  void initChannel(int port, bool broadcast) {
    RawDatagramSocket.bind(InternetAddress.anyIPv4, port).then((RawDatagramSocket socket) {
      socket.broadcastEnabled = broadcast;
      socket.listen((e) {
        Datagram? dg = socket.receive();
        if (dg != null) {
          _controller.add(dg.data);
        }
      });
    });
  }

  UdpReceiver() {
    initChannel(43211, true); //Skyradar
  }

  StreamSubscription<Uint8List> getStream() {
    return _controller.stream.listen((event) { });
  }
}