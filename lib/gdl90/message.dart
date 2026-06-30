import 'dart:typed_data';

abstract class Message
{
  int type;
  DateTime time = DateTime.now().toUtc();

  Message(this.type);

  void parse(Uint8List message);

  // Human-readable decoded fields, shown in the ADS-B message log.
  String decode() => "";

  // Optional short one-line label shown on the collapsed log row (e.g. the
  // list of FIS-B products carried by an uplink).
  String summary() => "";
}