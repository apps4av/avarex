import 'dart:async';
import 'dart:typed_data';

import 'package:avaremp/utils/app_log.dart';
import 'package:universal_io/io.dart';

/// Implements the Avidyne AviSDK "WiFiCrChannel" upload protocol in Dart.
///
/// The IFD exposes a command/response FMS protocol on TCP port 5666. A file
/// (see [AvidyneStoredRoute]) is transferred by:
///   1. sending a Request-Upload command carrying the file length,
///   2. receiving a Ready response that assigns an upload id,
///   3. sending the file as a sequence of <=247 byte data packets, each of
///      which is acknowledged, and
///   4. receiving a Done response after the final packet.
class AvidyneWifiChannel {
  static const int fmsProtocolPort = 5666;

  // Datasets.
  static const int datasetRoute = 1;
  static const int datasetUserWaypoint = 2;

  // Command kinds.
  static const int _cmdRequestUpload = 0x00;
  static const int _cmdUploadData = 0x40;

  // Response kinds.
  static const int _respReady = 0x80;
  static const int _respDone = 0x83;
  static const int _respPacketAck = 0x84;
  static const int _respPacketNak = 0x85;

  static const int _maxPayload = 247;
  static const int _maxRetries = 3;

  int _nextMessageId = 0;

  /// Uploads [fileBytes] as the given [dataset] to the IFD at [ipAddress].
  ///
  /// Returns null on success, or a human readable error string on failure.
  Future<String?> upload(
    String ipAddress,
    int dataset,
    Uint8List fileBytes, {
    Duration connectTimeout = const Duration(seconds: 8),
    Duration responseTimeout = const Duration(seconds: 5),
  }) async {
    Socket? socket;
    _SocketReader? reader;
    try {
      socket = await Socket.connect(ipAddress, fmsProtocolPort,
          timeout: connectTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      reader = _SocketReader(socket);

      // Step 1: request the upload.
      final int fileLength = fileBytes.length;
      socket.add(_buildUploadRequest(dataset, fileLength));
      await socket.flush();

      // Step 2: read the Ready response and extract the upload id.
      final Uint8List response = await reader.read(8, responseTimeout);
      if (response.length != 8 || !_checksumIsGood(response, 8)) {
        return "IFD gave a malformed response.";
      }
      if (response[0] != _respReady) {
        return "IFD refused the upload (${_subCodeName(response[5])}).";
      }
      final int uid = response[5];

      // Step 3 & 4: send packets and wait for acknowledgements.
      int offset = 0;
      int packetId = 0;
      while (offset < fileLength) {
        final int payloadSize = (fileLength - offset) > _maxPayload
            ? _maxPayload
            : (fileLength - offset);
        final Uint8List packet =
            _buildDataPacket(uid, packetId, fileBytes, offset, payloadSize);

        bool acked = false;
        for (int attempt = 0; attempt <= _maxRetries && !acked; attempt++) {
          socket.add(packet);
          await socket.flush();

          final Uint8List ack = await reader.read(8, responseTimeout);
          final bool lastPacket = (offset + payloadSize) >= fileLength;

          if (ack.length != 8 || !_checksumIsGood(ack, 8)) {
            continue; // resend on a garbled reply
          }
          if (ack[0] == _respDone && lastPacket) {
            acked = true;
            offset += payloadSize;
          } else if (ack[0] == _respPacketAck) {
            acked = true;
            offset += payloadSize;
            packetId = (packetId + 1) & 0xFF;
          } else if (ack[0] == _respPacketNak) {
            continue; // resend this packet
          } else {
            return "IFD rejected the transfer (${_subCodeName(ack[5])}).";
          }
        }

        if (!acked) {
          return "Timed out sending the flight plan to the IFD.";
        }
      }

      return null;
    } on TimeoutException {
      return "Timed out communicating with the IFD.";
    } catch (e) {
      AppLog.logMessage("Avidyne upload failed: $e");
      return "Failed to send to the IFD. Check the Wi-Fi connection.";
    } finally {
      try {
        await reader?.cancel();
        socket?.destroy();
      } catch (_) {}
    }
  }

  Uint8List _buildUploadRequest(int dataset, int fileLength) {
    final Uint8List b = Uint8List(11);
    _populateHeader(b, _cmdRequestUpload, 11);
    b[5] = dataset & 0xFF;
    b[6] = (fileLength >> 24) & 0xFF;
    b[7] = (fileLength >> 16) & 0xFF;
    b[8] = (fileLength >> 8) & 0xFF;
    b[9] = fileLength & 0xFF;
    b[10] = _checksum(b, 10);
    return b;
  }

  Uint8List _buildDataPacket(
      int uid, int packetId, Uint8List file, int offset, int payloadSize) {
    final int packetSize = 5 + 2 + payloadSize + 1;
    final Uint8List b = Uint8List(packetSize);
    _populateHeader(b, _cmdUploadData, packetSize);
    b[5] = uid & 0xFF;
    b[6] = packetId & 0xFF;
    for (int i = 0; i < payloadSize; i++) {
      b[7 + i] = file[offset + i];
    }
    b[packetSize - 1] = _checksum(b, packetSize - 1);
    return b;
  }

  void _populateHeader(Uint8List buffer, int command, int len) {
    buffer[0] = command & 0xFF;
    buffer[1] = _nextMessageId & 0xFF;
    _nextMessageId = (_nextMessageId + 1) & 0xFF;
    buffer[2] = len & 0xFF;
    buffer[3] = 0;
    buffer[4] = 0;
  }

  int _checksum(Uint8List buffer, int len) {
    int checksum = 0;
    for (int i = 0; i < len; i++) {
      checksum = (checksum + i + 1 + buffer[i]) & 0xFF;
    }
    return checksum;
  }

  bool _checksumIsGood(Uint8List buffer, int len) {
    return _checksum(buffer, len - 1) == buffer[len - 1];
  }

  String _subCodeName(int code) {
    switch (code) {
      case 1:
        return "busy";
      case 2:
        return "not supported";
      case 5:
        return "timed out";
      case 6:
        return "checksum error";
      case 7:
        return "file CRC error";
      case 8:
        return "invalid message length";
      default:
        return "error $code";
    }
  }
}

/// Buffers a socket's byte stream and hands out exactly the requested number of
/// bytes, with a timeout.
class _SocketReader {
  final BytesBuilder _buffer = BytesBuilder();
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _waiter;
  bool _closed = false;

  _SocketReader(Socket socket) {
    _subscription = socket.listen(
      (Uint8List data) {
        _buffer.add(data);
        _signal();
      },
      onError: (_) {
        _closed = true;
        _signal();
      },
      onDone: () {
        _closed = true;
        _signal();
      },
      cancelOnError: false,
    );
  }

  void _signal() {
    final Completer<void>? waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  Future<Uint8List> read(int n, Duration timeout) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (_buffer.length < n) {
      if (_closed) {
        break;
      }
      final Duration remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }
      _waiter = Completer<void>();
      try {
        await _waiter!.future.timeout(remaining);
      } on TimeoutException {
        break;
      }
    }

    final Uint8List all = _buffer.toBytes();
    _buffer.clear();
    if (all.length <= n) {
      return all;
    }
    // Keep any extra bytes for the next read.
    _buffer.add(all.sublist(n));
    return Uint8List.sublistView(all, 0, n);
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
