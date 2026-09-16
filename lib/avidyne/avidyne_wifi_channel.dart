import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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
enum _SdkDownloadState {
  machineIdle,
  startReceivingFile,
  waitingForDownloadStart,
  receivingPacket,
  resettingChannel,
  waitingForReset,
  downloadComplete,
}

class AvidyneWifiChannel {
  static const int fmsProtocolPort = 5666;

  // Datasets.
  static const int datasetRoute = 1;
  static const int datasetUserWaypoint = 2;

  // Command kinds (WiFiCrChannel::CommandKind).
  static const int _cmdRequestUpload = 0x00;
  static const int _cmdRequestDownload = 0x01;
  static const int _cmdStartDownload = 0x04;
  static const int _cmdResetSession = 0x3F;
  static const int _cmdUploadData = 0x40;
  static const int _cmdDownloadData = 0x41;

  // Response kinds (WiFiCrChannel::ResponseKind). eReady (0x80) answers both an
  // upload and a download request; eUnable/eFail are refusals whose reason is
  // in byte 5 (a ResponseSubCode).
  static const int _respReady = 0x80;
  static const int _respUnable = 0x81;
  static const int _respFail = 0x82;
  static const int _respDone = 0x83;
  static const int _respPacketAck = 0x84;
  static const int _respPacketNak = 0x85;

  // Response sub codes (see WiFiCrChannel::ResponseSubCode).
  static const int _subSuccess = 0;
  static const int _subBusy = 1;
  static const int _subInvalidDownloadId = 4;
  static const int _subTimedOut = 5;
  static const int _subChecksumError = 6;
  static const int _subInvalidLength = 8;
  static const int _subOutOfSequence = 13;
  static const int _subUnexpectedCommand = 14;

  static const int _maxPayload = 247;
  static const int _maxRetries = 3;

  // A stored route file is ~5 KB; cap well above that to reject nonsense.
  static const int _maxDownloadBytes = 256 * 1024;

  int _nextMessageId = 0;

  final AvidyneMessageLog _log = AvidyneMessageLog();

  // Download-side state mirrors AviSDK WiFiCrChannel::Run().  The SDK expects
  // Run() to be invoked every 50 ms; OneSecond is 20 Run() periods and
  // MaxRetries is 3.
  static const int _sdkOneSecondTicks = 20;
  static const Duration _sdkRunPeriod = Duration(milliseconds: 50);

  // Physical-IFD compatibility timing.
  //
  // Keep the SDK state machine and wire protocol unchanged, but allow the
  // physical IFD more time to produce Ready, packet 0, and Reset responses.
  // Packet NAKs remain on the SDK's nominal one-second cadence.
  static const int _downloadReadyWaitTicks = 80; // nominal 4 seconds
  static const int _downloadResetWaitTicks = 100; // nominal 5 seconds
  static const int _downloadPacketWaitTicks = _sdkOneSecondTicks;
  static const int _downloadMaxRetries = 12;

  Timer? _downloadRunTimer;
  _SdkDownloadState _sdkDownloadState = _SdkDownloadState.machineIdle;
  Completer<(Uint8List?, String?)>? _downloadCompleter;

  int _downloadDataset = 0;
  int _downloadMessageId = 0;
  int _downloadUid = 0;
  int _downloadFileLength = 0;
  int _downloadBytesRemaining = 0;
  int _downloadNextPacketId = 0;
  int _downloadRetryCount = 0;
  int _downloadWaitCount = 0;
  int _downloadLastBufferedLength = 0;
  BytesBuilder _downloadBody = BytesBuilder();
  Uint8List? _downloadCompletedFile;
  String? _downloadFailureAfterReset;

  // The AviSDK keeps one WiFiCrChannel/TCP connection open and services
  // successive operations over that same channel.  Keep the download-side
  // connection alive between import requests so we can duplicate that
  // behaviour more closely.
  Socket? _downloadSocket;
  _SocketReader? _downloadReader;
  String? _downloadIpAddress;

  Future<void> _ensureDownloadConnection(
      String ipAddress, Duration connectTimeout) async {
    if (_downloadSocket != null &&
        _downloadReader != null &&
        !_downloadReader!.closed &&
        _downloadIpAddress == ipAddress) {
      debugPrint('AVIDYNE SOCKET reusing persistent connection '
          'for $ipAddress:$fmsProtocolPort');
      return;
    }

    await close();

    debugPrint('AVIDYNE SOCKET opening persistent connection '
        'to $ipAddress:$fmsProtocolPort');

    final Socket socket = await _connect(ipAddress, connectTimeout);
    _downloadSocket = socket;
    _downloadReader = _SocketReader(socket);
    _downloadIpAddress = ipAddress;
  }

  /// Closes the persistent command/response channel.
  Future<void> close() async {
    _downloadRunTimer?.cancel();
    _downloadRunTimer = null;

    final Completer<(Uint8List?, String?)>? pending = _downloadCompleter;
    _downloadCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete((null, 'IFD channel closed.'));
    }
    _sdkDownloadState = _SdkDownloadState.machineIdle;
    final Socket? socket = _downloadSocket;
    final _SocketReader? reader = _downloadReader;

    _downloadSocket = null;
    _downloadReader = null;
    _downloadIpAddress = null;

    if (socket != null || reader != null) {
      debugPrint('AVIDYNE SOCKET closing persistent connection');
      await _closeGracefully(socket, reader);
    }
  }

  void _send(Socket socket, Uint8List bytes) {
    _log.logMessage(true, bytes);
    socket.add(bytes);
  }

  // Connects to the IFD's FMS port, retrying with a short backoff. The IFD
  // accepts only one client at a time, so right after a previous transfer it
  // can briefly refuse (or not answer) a new connection until it has released
  // the old socket; a couple of retries ride over that window.
  Future<Socket> _connect(String ipAddress, Duration totalTimeout) async {
    const int attempts = 3;
    final int perMs = totalTimeout.inMilliseconds ~/ attempts;
    final Duration perAttempt =
        Duration(milliseconds: perMs < 2500 ? 2500 : perMs);
    Object? lastError;
    for (int i = 0; i < attempts; i++) {
      try {
        debugPrint('AVIDYNE SOCKET connect attempt ${i + 1}/$attempts to '
            '$ipAddress:$fmsProtocolPort');

        final Socket socket = await Socket.connect(
          ipAddress,
          fmsProtocolPort,
          timeout: perAttempt,
        );
        socket.setOption(SocketOption.tcpNoDelay, true);

        debugPrint('AVIDYNE SOCKET connected local=${socket.address.address}:'
            '${socket.port} remote=${socket.remoteAddress.address}:'
            '${socket.remotePort}');

        return socket;
      } on SocketException catch (e) {
        lastError = e;
        debugPrint('AVIDYNE SOCKET connect attempt ${i + 1} failed: $e');
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint('AVIDYNE SOCKET connect attempt ${i + 1} timed out: $e');
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    throw lastError!;
  }

  // Closes the connection gracefully: flush queued bytes, then half-close with
  // a FIN (bounded by a short timeout) so the IFD sees a clean disconnect and
  // releases its transfer session promptly, instead of an abortive reset that
  // can leave the session lingering as "busy". Falls back to a hard destroy.
  Future<void> _closeGracefully(Socket? socket, _SocketReader? reader) async {
    if (socket != null) {
      debugPrint('AVIDYNE SOCKET closing');

      try {
        await socket.flush();
        debugPrint('AVIDYNE SOCKET final flush complete');
      } catch (e) {
        debugPrint('AVIDYNE SOCKET final flush failed: $e');
      }

      try {
        final bool closed = await Future.any<bool>(<Future<bool>>[
          socket.close().then((_) => true),
          Future<bool>.delayed(const Duration(seconds: 2), () => false),
        ]);

        debugPrint(closed
            ? 'AVIDYNE SOCKET close completed'
            : 'AVIDYNE SOCKET close timed out after 2 seconds');
      } catch (e) {
        debugPrint('AVIDYNE SOCKET close failed: $e');
      }
    }

    try {
      await reader?.cancel();
      debugPrint('AVIDYNE SOCKET reader cancelled');
    } catch (e) {
      debugPrint('AVIDYNE SOCKET reader cancel failed: $e');
    }

    try {
      socket?.destroy();
      if (socket != null) {
        debugPrint('AVIDYNE SOCKET destroyed');
      }
    } catch (e) {
      debugPrint('AVIDYNE SOCKET destroy failed: $e');
    }
  }

  Future<Uint8List> _recv(_SocketReader reader, int n, Duration timeout) async {
    final Uint8List bytes = await reader.read(n, timeout);
    if (bytes.isNotEmpty) {
      _log.logMessage(false, bytes);
    }
    return bytes;
  }

  // Reads one command/response message, whose length is carried in byte 2 of
  // the 5 byte header. Used for the variable length ready/refusal responses so
  // an 8 byte "unable" reply is not mistaken for a truncated 11 byte "ready".
  Future<Uint8List> _recvResponse(
      _SocketReader reader, Duration timeout) async {
    final Uint8List header = await reader.read(5, timeout);
    if (header.length != 5) {
      if (header.isNotEmpty) {
        _log.logMessage(false, header);
      }
      return header;
    }
    final int msgLen = header[2];
    if (msgLen < 6 || msgLen > 32) {
      _log.logMessage(false, header);
      return header; // implausible length -> caller treats as malformed
    }
    final Uint8List rest = await reader.read(msgLen - 5, timeout);
    final Uint8List packet = Uint8List(5 + rest.length)
      ..setRange(0, 5, header)
      ..setRange(5, 5 + rest.length, rest);
    _log.logMessage(false, packet);
    return packet;
  }

  // Reads one complete protocol message. Unlike _recvResponse(), this accepts
  // the full 8-bit message length, because stale Download-Data packets can be
  // present on a persistent socket while we are waiting for a command response.
  Future<Uint8List> _recvProtocolMessage(
      _SocketReader reader, Duration timeout) async {
    final Uint8List header = await reader.read(5, timeout);

    if (header.length != 5) {
      if (header.isNotEmpty) {
        _log.logMessage(false, header);
      }
      return header;
    }

    final int msgLen = header[2];

    if (msgLen < 6) {
      _log.logMessage(false, header);
      return header;
    }

    final Uint8List rest = await reader.read(msgLen - 5, timeout);

    final Uint8List packet = Uint8List(5 + rest.length)
      ..setRange(0, 5, header)
      ..setRange(5, 5 + rest.length, rest);

    _log.logMessage(false, packet);
    return packet;
  }

  // Waits for the response belonging to [messageId]. A persistent IFD channel
  // can still contain retransmitted Download-Data from the previous transfer,
  // or a late response to an earlier command. Consume and ignore those instead
  // of letting them become the response to the new command.
  Future<Uint8List> _waitForCommandResponse(
    _SocketReader reader,
    int messageId,
    Duration timeout,
  ) async {
    final DateTime deadline = DateTime.now().add(timeout);

    while (true) {
      final Duration remaining = deadline.difference(DateTime.now());

      if (remaining <= Duration.zero) {
        debugPrint('AVIDYNE response wait timed out for messageId=$messageId');
        return Uint8List(0);
      }

      final Uint8List packet = await _recvProtocolMessage(reader, remaining);

      if (packet.isEmpty) {
        return packet;
      }

      // We cannot safely classify a packet without at least the fixed header.
      if (packet.length < 5) {
        return packet;
      }

      final int command = packet[0];

      if (command == _cmdDownloadData) {
        final int uid = packet.length > 5 ? packet[5] : -1;
        final int packetId = packet.length > 6 ? packet[6] : -1;

        debugPrint('AVIDYNE ignoring stale Download-Data '
            'uid=$uid pkt=$packetId while waiting for '
            'messageId=$messageId');
        continue;
      }

      if (packet.length < 2) {
        return packet;
      }

      if (packet[1] != messageId) {
        debugPrint('AVIDYNE ignoring stale response '
            'command=0x${command.toRadixString(16).padLeft(2, '0')} '
            'messageId=${packet[1]} while waiting for '
            'messageId=$messageId');
        continue;
      }

      return packet;
    }
  }

  // True if the IFD refused a request because a transfer session is still
  // active (eUnable/eFail with the eBusy sub code).
  bool _isBusy(Uint8List response) {
    return response.length >= 8 &&
        (response[0] == _respUnable || response[0] == _respFail) &&
        response[5] == _subBusy;
  }

  // Sends a reset-session command to return the IFD channel to its idle state
  // and waits for the eReady acknowledgement. Returns null on success.
  Future<String?> _resetSession(
      Socket socket, _SocketReader reader, Duration timeout) async {
    final Uint8List reset = _buildResetSession();
    final int resetMessageId = reset[1];

    _send(socket, reset);
    await socket.flush();

    final Uint8List resp =
        await _waitForCommandResponse(reader, resetMessageId, timeout);
    if (resp.length < 8 || !_checksumIsGood(resp, resp.length)) {
      return "IFD gave a malformed reset response.";
    }
    if (resp[0] != _respReady) {
      return "IFD could not clear its busy session (${_subCodeName(resp[5])}).";
    }
    return null;
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
      socket = await _connect(ipAddress, connectTimeout);
      reader = _SocketReader(socket);

      // Step 1: request the upload.
      final int fileLength = fileBytes.length;
      _send(socket, _buildUploadRequest(dataset, fileLength));
      await socket.flush();

      // Step 2: read the Ready response and extract the upload id.
      Uint8List response = await _recvResponse(reader, responseTimeout);
      if (response.length < 8 || !_checksumIsGood(response, response.length)) {
        return "IFD gave a malformed response.";
      }
      // A stale session left over from an interrupted transfer makes the IFD
      // answer "unable: busy". Reset the channel and request the upload again.
      if (_isBusy(response)) {
        final String? resetError =
            await _resetSession(socket, reader, responseTimeout);
        if (resetError != null) {
          return resetError;
        }
        _send(socket, _buildUploadRequest(dataset, fileLength));
        await socket.flush();
        response = await _recvResponse(reader, responseTimeout);
        if (response.length < 8 ||
            !_checksumIsGood(response, response.length)) {
          return "IFD gave a malformed response.";
        }
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
    } on SocketException catch (e) {
      AppLog.logMessage("Avidyne upload connection failed: $e");
      return "Could not reach the IFD. It may still be finishing a previous "
          "transfer \u2014 wait a few seconds and try again.";
    } on TimeoutException {
      return "Timed out communicating with the IFD.";
    } catch (e) {
      AppLog.logMessage("Avidyne upload failed: $e");
      return "Failed to send to the IFD. Check the Wi-Fi connection.";
    } finally {
      await _closeGracefully(socket, reader);
    }
  }

  /// Downloads [dataset] using a periodic state machine modeled directly on
  /// AviSDK WiFiCrChannel::Run().  The public Future keeps AvareX's existing
  /// API while the wire protocol advances one state every 50 ms.
  Future<(Uint8List?, String?)> download(
    String ipAddress,
    int dataset, {
    Duration connectTimeout = const Duration(seconds: 8),
    Duration responseTimeout = const Duration(seconds: 8),
  }) async {
    try {
      await _ensureDownloadConnection(ipAddress, connectTimeout);
      _startSdkDownloadRunner();

      if (_sdkDownloadState != _SdkDownloadState.machineIdle ||
          _downloadCompleter != null) {
        return (null, 'IFD command/response channel is busy.');
      }

      // responseTimeout is intentionally not used here.  The AviSDK download
      // path uses OneSecond == 20 Run() calls and MaxRetries == 3 rather than
      // a caller-supplied response timeout.
      _downloadDataset = dataset;
      _downloadMessageId = 0;
      _downloadUid = 0;
      _downloadFileLength = 0;
      _downloadBytesRemaining = 0;
      _downloadNextPacketId = 0;
      _downloadRetryCount = 0;
      _downloadWaitCount = 0;
      _downloadLastBufferedLength = _downloadReader?.bufferedLength ?? 0;
      _downloadBody = BytesBuilder();
      _downloadCompletedFile = null;
      _downloadFailureAfterReset = null;

      final Completer<(Uint8List?, String?)> completer =
          Completer<(Uint8List?, String?)>();
      _downloadCompleter = completer;
      _sdkDownloadState = _SdkDownloadState.startReceivingFile;

      debugPrint('AVIDYNE SDK Download() accepted dataset=$dataset');
      return await completer.future;
    } on SocketException catch (e) {
      AppLog.logMessage('Avidyne download connection failed: $e');
      await close();
      return (null, 'Could not reach the IFD. Check the Wi-Fi connection.');
    } on TimeoutException catch (e) {
      AppLog.logMessage('Avidyne download connection timed out: $e');
      await close();
      return (null, 'Timed out connecting to the IFD.');
    } catch (e) {
      AppLog.logMessage('Avidyne download failed: $e');
      return (null, 'Failed to read from the IFD. Check the Wi-Fi connection.');
    }
  }

  void _startSdkDownloadRunner() {
    if (_downloadRunTimer != null) {
      return;
    }

    _downloadRunTimer = Timer.periodic(_sdkRunPeriod, (_) {
      _runSdkDownloadTick();
    });
  }

  void _runSdkDownloadTick() {
    final Socket? socket = _downloadSocket;
    final _SocketReader? reader = _downloadReader;

    if (socket == null || reader == null) {
      return;
    }

    if (reader.closed) {
      _handleSdkSocketClosed();
      return;
    }

    switch (_sdkDownloadState) {
      case _SdkDownloadState.machineIdle:
        // WiFiCrChannel::Run(), eMachineIdle: Receive(buffer, 256) and ignore
        // anything that arrived while no operation is active.
        final int discarded = reader.discardBuffered();
        if (discarded != 0) {
          debugPrint('AVIDYNE SDK idle discarded $discarded byte(s)');
        }
        _downloadLastBufferedLength = 0;
        break;

      case _SdkDownloadState.startReceivingFile:
        final Uint8List request = _buildDownloadRequest(_downloadDataset);
        _downloadMessageId = request[1];
        _send(socket, request);
        _downloadWaitCount = _downloadReadyWaitTicks;
        _downloadLastBufferedLength = reader.bufferedLength;
        _sdkDownloadState = _SdkDownloadState.waitingForDownloadStart;
        debugPrint('AVIDYNE SDK -> eWaitingForDownloadStart '
            'messageId=$_downloadMessageId wait=$_downloadWaitCount');
        break;

      case _SdkDownloadState.waitingForDownloadStart:
        _sdkWaitingForDownloadStart(socket, reader);
        break;

      case _SdkDownloadState.receivingPacket:
        _sdkReceivingPacket(socket, reader);
        break;

      case _SdkDownloadState.resettingChannel:
        final Uint8List reset = _buildResetSession();
        _send(socket, reset);
        _downloadWaitCount = _downloadResetWaitTicks;
        _downloadLastBufferedLength = reader.bufferedLength;
        _sdkDownloadState = _SdkDownloadState.waitingForReset;
        debugPrint('AVIDYNE SDK -> eWaitingForReset '
            'messageId=${reset[1]} wait=$_downloadWaitCount');
        break;

      case _SdkDownloadState.waitingForReset:
        _sdkWaitingForReset(reader);
        break;

      case _SdkDownloadState.downloadComplete:
        // The SDK has no explicit case for eDownloadComplete; on the next
        // Run() it falls through the default/eMachineIdle path.  Do the same
        // idle receive/discard, then expose the completed file to AvareX.
        reader.discardBuffered();
        final Uint8List? file = _downloadCompletedFile;
        _downloadCompletedFile = null;
        _sdkDownloadState = _SdkDownloadState.machineIdle;
        if (file == null) {
          _completeSdkDownloadError('The downloaded flight plan was corrupt.');
        } else {
          _completeSdkDownloadSuccess(file);
        }
        break;
    }
  }

  void _sdkWaitingForDownloadStart(Socket socket, _SocketReader reader) {
    final Uint8List? packet = reader.takeProtocolMessage();

    if (packet != null) {
      _downloadLastBufferedLength = reader.bufferedLength;
      _log.logMessage(false, packet);

      // Match SDK order exactly: checksum, command, length, then message ID.
      if (!_checksumIsGood(packet, packet.length)) {
        debugPrint('AVIDYNE SDK Ready checksum error; remaining in state');
        return;
      }

      if (packet[0] != _respReady) {
        final int subCode =
            packet.length > 5 ? packet[5] : _subUnexpectedCommand;
        _sdkDownloadState = _SdkDownloadState.machineIdle;
        _completeSdkDownloadError(
            'IFD refused the download (${_subCodeName(subCode)}).');
        return;
      }

      if (packet.length != 11) {
        _sdkDownloadState = _SdkDownloadState.machineIdle;
        _completeSdkDownloadError('IFD gave a malformed download response.');
        return;
      }

      // The SDK assigns m_uid before checking the request message ID.
      _downloadUid = packet[5];

      if (packet[1] != _downloadMessageId) {
        debugPrint('AVIDYNE SDK Ready messageId ${packet[1]} does not match '
            '$_downloadMessageId; remaining in eWaitingForDownloadStart');
        return;
      }

      _downloadFileLength =
          (packet[6] << 24) | (packet[7] << 16) | (packet[8] << 8) | packet[9];

      // The C++ SDK writes to a temporary file. AvareX keeps the compressed
      // bytes in memory, but retains a conservative application safety cap.
      if (_downloadFileLength <= 0 || _downloadFileLength > _maxDownloadBytes) {
        _sdkDownloadState = _SdkDownloadState.machineIdle;
        _completeSdkDownloadError('IFD reported an invalid flight plan size.');
        return;
      }

      _downloadBytesRemaining = _downloadFileLength;
      _downloadBody = BytesBuilder();
      _downloadNextPacketId = 0;
      _downloadRetryCount = _downloadMaxRetries;
      _downloadWaitCount = _downloadPacketWaitTicks;
      _downloadLastBufferedLength = reader.bufferedLength;
      _sdkDownloadState = _SdkDownloadState.receivingPacket;

      // WiFiCrChannel sends StartDownload immediately in the same Run() call.
      _send(socket, _buildStartDownload(_downloadUid));
      debugPrint('AVIDYNE SDK -> eReceivingPacket uid=$_downloadUid '
          'bytes=$_downloadFileLength retries=$_downloadRetryCount');
      return;
    }

    // A partial TCP message is deliberately preserved by _SocketReader.  The
    // C++ TcpSocket API presents Receive() data directly; approximate that
    // activity without discarding a partial Dart TCP frame by consuming one
    // Run() period whenever new bytes appeared.
    final int buffered = reader.bufferedLength;
    if (buffered > _downloadLastBufferedLength) {
      _downloadLastBufferedLength = buffered;
      return;
    }

    if (--_downloadWaitCount < 0) {
      _downloadWaitCount = 0;
      _downloadFailureAfterReset =
          'Timed out waiting for the IFD to start the download.';
      _sdkDownloadState = _SdkDownloadState.resettingChannel;
      debugPrint('AVIDYNE SDK Ready timeout -> Reset()');
    }
  }

  void _sdkReceivingPacket(Socket socket, _SocketReader reader) {
    final Uint8List? packet = reader.takeProtocolMessage();

    if (packet != null) {
      _downloadLastBufferedLength = reader.bufferedLength;
      _downloadWaitCount = _sdkOneSecondTicks;
      _log.logMessage(false, packet);

      int responseKind = _respReady;
      int responseSubCode = _subSuccess;
      int responsePacketId = _downloadNextPacketId;
      String? terminalError;

      if (packet.length < 8) {
        responseKind = _respPacketNak;
        responseSubCode = _subInvalidLength;
      } else if (!_checksumIsGood(packet, packet.length)) {
        responseKind = _respPacketNak;
        responseSubCode = _subChecksumError;
      } else if (packet[0] != _cmdDownloadData) {
        responseKind = _respFail;
        responseSubCode = _subUnexpectedCommand;
        _sdkDownloadState = _SdkDownloadState.machineIdle;
        terminalError =
            'IFD aborted the download (${_subCodeName(responseSubCode)}).';
      } else {
        final int messageLen = packet[2];

        if (packet.length != messageLen) {
          responseKind = _respPacketNak;
          responseSubCode = _subInvalidLength;
        } else if (packet[5] != _downloadUid) {
          responseKind = _respFail;
          responseSubCode = _subInvalidDownloadId;
          _sdkDownloadState = _SdkDownloadState.machineIdle;
          terminalError = 'IFD download id mismatch.';
        } else {
          final int packetId = packet[6];
          responsePacketId = _downloadNextPacketId;

          if (packetId != _downloadNextPacketId) {
            responseKind = _respPacketNak;
            responseSubCode = _subOutOfSequence;
          } else {
            // Match WiFiCrChannel.cpp literally: messageLen - 8 and <= 248.
            final int numBytes = messageLen - 8;

            if (numBytes <= 0 || numBytes > 248) {
              responseKind = _respPacketNak;
              responseSubCode = _subInvalidLength;
            } else if (_downloadBytesRemaining < numBytes) {
              responseKind = _respPacketNak;
              responseSubCode = _subInvalidLength;
            } else {
              _downloadBody.add(packet.sublist(7, 7 + numBytes));
              _downloadNextPacketId = (_downloadNextPacketId + 1) & 0xFF;
              _downloadBytesRemaining -= numBytes;

              responseKind = _respPacketAck;
              responseSubCode = _subSuccess;
              responsePacketId = packetId;

              if (_downloadBytesRemaining <= 0) {
                final Uint8List raw = _downloadBody.toBytes();
                final Uint8List? file =
                    AvidyneStoredRoute.decompressDownload(raw);

                if (file != null) {
                  _downloadCompletedFile = file;
                  _sdkDownloadState = _SdkDownloadState.downloadComplete;
                } else {
                  _sdkDownloadState = _SdkDownloadState.machineIdle;
                  terminalError = 'The downloaded flight plan was corrupt.';
                }
              }
            }
          }
        }
      }

      _send(
        socket,
        _buildSdkDownloadResponse(
          responseKind,
          _downloadUid,
          responsePacketId,
          responseSubCode,
        ),
      );

      if (terminalError != null) {
        _completeSdkDownloadError(terminalError);
      }
      return;
    }

    // Preserve partial Dart TCP data.  In the SDK, any nonzero Receive()
    // resets m_waitCount to OneSecond while staying in eReceivingPacket.
    final int buffered = reader.bufferedLength;
    if (buffered > _downloadLastBufferedLength) {
      _downloadLastBufferedLength = buffered;
      _downloadWaitCount = _downloadPacketWaitTicks;
      return;
    }

    if (--_downloadWaitCount < 0) {
      final int responsePacketId = _downloadNextPacketId;
      int responseKind = _respPacketNak;
      int responseSubCode = _subInvalidLength;

      // Match the SDK's pre-decrement exactly. Starting at MaxRetries=3 gives
      // three PacketNak responses, then a Fail/eTimedOut on the fourth expiry.
      if (--_downloadRetryCount < 0) {
        responseKind = _respFail;
        responseSubCode = _subTimedOut;
        _downloadFailureAfterReset =
            'Timed out receiving the flight plan from the IFD.';
        _sdkDownloadState = _SdkDownloadState.resettingChannel;
      } else {
        _downloadWaitCount = _downloadPacketWaitTicks;
      }

      _send(
        socket,
        _buildSdkDownloadResponse(
          responseKind,
          _downloadUid,
          responsePacketId,
          responseSubCode,
        ),
      );

      if (responseKind == _respFail) {
        debugPrint('AVIDYNE SDK packet $responsePacketId retries exhausted; '
            'Reset()');
      } else {
        debugPrint('AVIDYNE SDK packet $responsePacketId timeout; '
            'NAK, retries remaining=$_downloadRetryCount');
      }
    }
  }

  void _sdkWaitingForReset(_SocketReader reader) {
    final Uint8List? packet = reader.takeProtocolMessage();

    if (packet != null) {
      _downloadLastBufferedLength = reader.bufferedLength;
      _log.logMessage(false, packet);

      // SDK eWaitingForReset reports malformed responses but stays in the
      // state.  Only a valid 8-byte Ready returns the channel to idle.
      if (packet.length != 8) {
        return;
      }
      if (!_checksumIsGood(packet, 8)) {
        return;
      }
      if (packet[0] != _respReady) {
        return;
      }

      _sdkDownloadState = _SdkDownloadState.machineIdle;
      final String error = _downloadFailureAfterReset ??
          'The IFD command/response channel was reset.';
      _downloadFailureAfterReset = null;
      _completeSdkDownloadError(error);
      return;
    }

    final int buffered = reader.bufferedLength;
    if (buffered > _downloadLastBufferedLength) {
      _downloadLastBufferedLength = buffered;
      return;
    }

    if (--_downloadWaitCount < 0) {
      _downloadWaitCount = 0;
      _sdkDownloadState = _SdkDownloadState.machineIdle;
      final String error = _downloadFailureAfterReset ??
          'Timed out resetting the IFD command/response channel.';
      _downloadFailureAfterReset = null;
      _completeSdkDownloadError(error);
    }
  }

  Uint8List _buildSdkDownloadResponse(
      int kind, int uid, int packetId, int subCode) {
    final Uint8List response = Uint8List(8);
    _populateHeader(response, _respReady, 8);
    response[0] = kind & 0xFF;
    response[1] = uid & 0xFF;
    response[5] = subCode & 0xFF;
    response[6] = packetId & 0xFF;
    response[7] = _checksum(response, 7);
    return response;
  }

  void _completeSdkDownloadSuccess(Uint8List file) {
    final Completer<(Uint8List?, String?)>? completer = _downloadCompleter;
    _downloadCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete((file, null));
    }
  }

  void _completeSdkDownloadError(String error) {
    final Completer<(Uint8List?, String?)>? completer = _downloadCompleter;
    _downloadCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete((null, error));
    }
  }

  void _handleSdkSocketClosed() {
    _downloadRunTimer?.cancel();
    _downloadRunTimer = null;

    final Socket? socket = _downloadSocket;
    _downloadSocket = null;
    _downloadReader = null;
    _downloadIpAddress = null;
    try {
      socket?.destroy();
    } catch (_) {}

    _sdkDownloadState = _SdkDownloadState.machineIdle;
    _completeSdkDownloadError('The IFD closed the Wi-Fi connection.');
  }

  Uint8List _buildDownloadRequest(int dataset) {
    final Uint8List b = Uint8List(8);
    _populateHeader(b, _cmdRequestDownload, 8);
    b[5] = dataset & 0xFF;
    b[6] = 0; // meta data
    b[7] = _checksum(b, 7);
    return b;
  }

  Uint8List _buildResetSession() {
    final Uint8List b = Uint8List(6);
    _populateHeader(b, _cmdResetSession, 6);
    b[5] = _checksum(b, 5);
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
      onError: (Object error) {
        debugPrint('AVIDYNE SOCKET receive error: $error');
        _closed = true;
        _signal();
      },
      onDone: () {
        debugPrint('AVIDYNE SOCKET peer closed receive stream');
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

    // A TCP read may split an application message anywhere.  If the timeout
    // expires with only part of the requested data buffered, leave those bytes
    // in place for the next read instead of throwing them away.
    if (_buffer.length < n && !_closed) {
      if (_buffer.length > 0) {
        debugPrint('AVIDYNE SOCKET partial read buffered '
            '${_buffer.length}/$n bytes at timeout');
      }
      return Uint8List(0);
    }

    final Uint8List all = _buffer.toBytes();

    // If the peer closed, return whatever remains so callers can diagnose the
    // truncated message.
    if (all.length < n) {
      _buffer.clear();
      return all;
    }

    _buffer.clear();

    if (all.length > n) {
      _buffer.add(all.sublist(n));
    }

    return Uint8List.sublistView(all, 0, n);
  }

  /// Discards bytes that arrived while the command/response channel was idle.
  ///
  /// AviSDK WiFiCrChannel::Run() continuously calls Receive() in
  /// eMachineIdle specifically so stale/late traffic cannot become the
  /// response to the next command.
  Uint8List drainBuffered() {
    final Uint8List bytes = _buffer.toBytes();
    _buffer.clear();
    return bytes;
  }

  int get bufferedLength => _buffer.length;
  bool get closed => _closed;

  /// Returns one complete protocol message if one is already buffered.
  /// No waiting occurs here; the SDK-style 50-ms runner owns the timing.
  Uint8List? takeProtocolMessage() {
    if (_buffer.length < 5) {
      return null;
    }

    final Uint8List all = _buffer.toBytes();
    final int declaredLength = all[2];
    final int messageLength = declaredLength < 5 ? 5 : declaredLength;

    if (all.length < messageLength) {
      return null;
    }

    _buffer.clear();
    if (all.length > messageLength) {
      _buffer.add(all.sublist(messageLength));
    }

    return Uint8List.fromList(all.sublist(0, messageLength));
  }

  /// SDK eMachineIdle calls Receive(buffer, 256) and discards what it gets.
  /// With Dart's stream buffer, dropping everything currently buffered is the
  /// closest equivalent and prevents late packets from becoming a later Ready.
  int discardBuffered() {
    final int count = _buffer.length;
    if (count != 0) {
      _buffer.clear();
    }
    return count;
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
