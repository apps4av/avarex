import 'dart:async';
import 'dart:typed_data';

// Web stub: UDP sockets are not available in browsers. Provide an inert stream.
class UdpReceiver {
  late StreamController<Uint8List> _controller;

  void initChannel(int port, bool broadcast) {}

  StreamSubscription<Uint8List> getStream(List<int> ports, List<bool> isBroadcast) {
    _controller = StreamController<Uint8List>();
    return _controller.stream.listen((_) {});
  }

  void finish() {
    _controller.close();
  }
}
