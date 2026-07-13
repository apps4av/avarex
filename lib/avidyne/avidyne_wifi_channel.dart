import 'dart:async';
import 'dart:typed_data';

import 'package:avaremp/avidyne/avidyne_message_log.dart';
import 'package:avaremp/avidyne/avidyne_stored_route.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:universal_io/io.dart';

/// Implements the Avidyne AviSDK "WiFiCrChannel" upload/download protocol in
/// Dart.
///
/// The IFD exposes a command/response FMS protocol on TCP port 5666. A file
/// (see [AvidyneStoredRoute]) is uploaded by:
///   1. sending a Request-Upload command carrying the file length,
///   2. receiving a Ready response that assigns an upload id,
///   3. sending the file as a sequence of <=247 byte data packets, each of
///      which is acknowledged, and
///   4. receiving a Done response after the final packet.
///
/// A download runs the mirror image: a Request-Download command, a Ready
/// response carrying the (compressed) file length and a download id, a
/// Start-Download acknowledgement, then a stream of data packets that the app
/// acknowledges one by one. The received file is RLE compressed with a small
/// header and a trailing Fletcher checksum (see
/// [AvidyneStoredRoute.decompressDownload]).
class AvidyneWifiChannel {
  static const int fmsProtocolPort = 5666;

  // Datasets.
  static const int datasetRoute = 1;
  static const int datasetUserWaypoint = 2;

  // Command kinds.
  static const int _cmdRequestUpload = 0x00;
  static const int _cmdRequestDownload = 0x01;
  static const int _cmdStartDownload = 0x04;
  static const int _cmdUploadData = 0x40;
  static const int _cmdDownloadData = 0x41;

  // Response kinds.
  static const int _respReady = 0x80;
  static const int _respDone = 0x83;
  static const int _respPacketAck = 0x84;
  static const int _respPacketNak = 0x85;

  // Response sub codes (see WiFiCrChannel::ResponseSubCode).
  static const int _subSuccess = 0;
  static const int _subChecksumError = 6;
  static const int _subInvalidLength = 8;
  static const int _subOutOfSequence = 13;

  static const int _maxPayload = 247;
  static const int _maxRetries = 3;

  // A stored route file is ~5 KB; cap well above that to reject nonsense.
  static const int _maxDownloadBytes = 256 * 1024;

  int _nextMessageId = 0;

  final AvidyneMessageLog _log = AvidyneMessageLog();

  void _send(Socket socket, Uint8List bytes) {
    _log.logMessage(true, bytes);
    socket.add(bytes);
  }

  Future<Uint8List> _recv(_SocketReader reader, int n, Duration timeout) async {
    final Uint8List bytes = await reader.read(n, timeout);
    if (bytes.isNotEmpty) {
      _log.logMessage(false, bytes);
    }
    return bytes;
  }

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
      _send(socket, _buildUploadRequest(dataset, fileLength));
      await socket.flush();

      // Step 2: read the Ready response and extract the upload id.
      final Uint8List response = await _recv(reader, 8, responseTimeout);
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
          _send(socket, packet);
          await socket.flush();

          final Uint8List ack = await _recv(reader, 8, responseTimeout);
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

  /// Downloads the given [dataset] from the IFD at [ipAddress].
  ///
  /// Returns a record of (decompressed file bytes, error). Exactly one is
  /// non-null. On success the bytes are a stored-route file that
  /// [AvidyneStoredRoute.parseRouteFile] can decode.
  Future<(Uint8List?, String?)> download(
    String ipAddress,
    int dataset, {
    Duration connectTimeout = const Duration(seconds: 8),
    Duration responseTimeout = const Duration(seconds: 8),
  }) async {
    Socket? socket;
    _SocketReader? reader;
    try {
      socket = await Socket.connect(ipAddress, fmsProtocolPort,
          timeout: connectTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      reader = _SocketReader(socket);

      // Step 1: request the download. Remember the message id so we can match
      // it against the Ready response.
      final int requestId = _nextMessageId & 0xFF;
      _send(socket, _buildDownloadRequest(dataset));
      await socket.flush();

      // Step 2: read the Ready response (11 bytes) with file length + uid.
      final Uint8List ready = await _recv(reader, 11, responseTimeout);
      if (ready.length != 11 || !_checksumIsGood(ready, 11)) {
        return (null, "IFD gave a malformed download response.");
      }
      if (ready[0] != _respReady) {
        return (null, "IFD refused the download (${_subCodeName(ready[5])}).");
      }
      if (ready[1] != requestId) {
        return (null, "IFD download response was out of sequence.");
      }
      final int uid = ready[5];
      final int fileLength =
          (ready[6] << 24) | (ready[7] << 16) | (ready[8] << 8) | ready[9];
      if (fileLength <= 0 || fileLength > _maxDownloadBytes) {
        return (null, "IFD reported an invalid flight plan size.");
      }

      // Step 3: tell the IFD we are ready to start receiving.
      _send(socket, _buildStartDownload(uid));
      await socket.flush();

      // Step 4: receive data packets, acknowledging each, until complete.
      final BytesBuilder bodyBuilder = BytesBuilder();
      int expectedPacketId = 0;
      int remaining = fileLength;
      int retries = 0;

      while (remaining > 0) {
        // Read header then body as one logical message for the hex log.
        final Uint8List header = await reader.read(5, responseTimeout);
        if (header.length != 5) {
          return (null, "Timed out receiving the flight plan from the IFD.");
        }
        final int cmd = header[0];
        final int msgLen = header[2];
        if (msgLen < 8) {
          _log.logMessage(false, header);
          return (null, "IFD sent a malformed packet.");
        }
        final Uint8List rest = await reader.read(msgLen - 5, responseTimeout);
        if (rest.length != msgLen - 5) {
          _log.logMessage(false, header);
          return (null, "Timed out receiving the flight plan from the IFD.");
        }
        final Uint8List packet = Uint8List(msgLen)
          ..setRange(0, 5, header)
          ..setRange(5, msgLen, rest);
        _log.logMessage(false, packet);

        if (cmd != _cmdDownloadData) {
          // Unable / Fail / unexpected command.
          return (null, "IFD aborted the download (${_subCodeName(packet[5])}).");
        }
        if (!_checksumIsGood(packet, msgLen)) {
          _send(socket, _buildDownloadNak(uid, expectedPacketId, _subChecksumError));
          await socket.flush();
          if (++retries > _maxRetries) {
            return (null, "Too many errors downloading the flight plan.");
          }
          continue;
        }
        if (packet[5] != uid) {
          return (null, "IFD download id mismatch.");
        }
        final int packetId = packet[6];
        if (packetId != expectedPacketId) {
          _send(socket, _buildDownloadNak(uid, expectedPacketId, _subOutOfSequence));
          await socket.flush();
          if (++retries > _maxRetries) {
            return (null, "Too many errors downloading the flight plan.");
          }
          continue;
        }
        final int numBytes = msgLen - 8;
        if (numBytes <= 0 || numBytes > remaining) {
          _send(socket, _buildDownloadNak(uid, expectedPacketId, _subInvalidLength));
          await socket.flush();
          if (++retries > _maxRetries) {
            return (null, "Too many errors downloading the flight plan.");
          }
          continue;
        }

        bodyBuilder.add(packet.sublist(7, 7 + numBytes));
        remaining -= numBytes;
        retries = 0;

        _send(socket, _buildDownloadAck(uid, packetId));
        await socket.flush();
        expectedPacketId = (expectedPacketId + 1) & 0xFF;
      }

      final Uint8List raw = bodyBuilder.toBytes();
      final Uint8List? file = AvidyneStoredRoute.decompressDownload(raw);
      if (file == null) {
        return (null, "The downloaded flight plan was corrupt.");
      }
      return (file, null);
    } on TimeoutException {
      return (null, "Timed out communicating with the IFD.");
    } catch (e) {
      AppLog.logMessage("Avidyne download failed: $e");
      return (null, "Failed to read from the IFD. Check the Wi-Fi connection.");
    } finally {
      try {
        await reader?.cancel();
        socket?.destroy();
      } catch (_) {}
    }
  }

  Uint8List _buildDownloadRequest(int dataset) {
    final Uint8List b = Uint8List(8);
    _populateHeader(b, _cmdRequestDownload, 8);
    b[5] = dataset & 0xFF;
    b[6] = 0; // meta data
    b[7] = _checksum(b, 7);
    return b;
  }

  Uint8List _buildStartDownload(int uid) {
    final Uint8List b = Uint8List(8);
    _populateHeader(b, _cmdStartDownload, 8);
    b[1] = uid & 0xFF; // message id is overridden with the uid for downloads
    b[5] = uid & 0xFF;
    b[6] = 0;
    b[7] = _checksum(b, 7);
    return b;
  }

  Uint8List _buildDownloadAck(int uid, int packetId) {
    final Uint8List b = Uint8List(8);
    _populateHeader(b, _respPacketAck, 8);
    b[1] = uid & 0xFF;
    b[5] = _subSuccess;
    b[6] = packetId & 0xFF;
    b[7] = _checksum(b, 7);
    return b;
  }

  Uint8List _buildDownloadNak(int uid, int expectedPacketId, int subCode) {
    final Uint8List b = Uint8List(8);
    _populateHeader(b, _respPacketNak, 8);
    b[1] = uid & 0xFF;
    b[5] = subCode & 0xFF;
    b[6] = expectedPacketId & 0xFF;
    b[7] = _checksum(b, 7);
    return b;
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
      case 4:
        return "invalid download id";
      case 5:
        return "timed out";
      case 6:
        return "checksum error";
      case 7:
        return "file CRC error";
      case 8:
        return "invalid message length";
      case 12:
        return "no download active";
      case 13:
        return "packet out of sequence";
      case 14:
        return "unexpected command";
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
