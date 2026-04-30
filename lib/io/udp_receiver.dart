import 'package:avaremp/storage.dart';
import 'package:universal_io/io.dart';

import 'package:avaremp/utils/app_log.dart';

// Get UDP from receivers, handle GDL90
class UdpReceiver {

  final List<RawDatagramSocket> _sockets = [];

  void initChannel(int port, bool broadcast) async {
    try {
      RawDatagramSocket socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, port, reuseAddress: true).then((
          RawDatagramSocket socket) {
        socket.broadcastEnabled = broadcast;
        socket.listen((e) {
          // Drain the kernel queue: one listen event can signal multiple datagrams.
          // A single receive() drops the rest and corrupts GDL90 byte alignment (bad 0x7E framing → CRC failures).
          while (true) {
            Datagram? dg = socket.receive();
            if (dg == null) {
              break;
            }
            Storage().nmeaBuffer.put(dg.data);
            Storage().gdl90Buffer.put(dg.data);
          }
        });
        return socket;
      });
      _sockets.add(socket);
    }
    catch(e) {
      AppLog.logMessage("UDP listen error: $e");
    }
  }

  void start(List<int> ports, List<bool> isBroadcast) {
    for(int port in ports) {
      initChannel(port, isBroadcast[ports.indexOf(port)]);
    }
  }

  void finish() {
    for(RawDatagramSocket socket in _sockets) {
      socket.close();
    }
  }
}