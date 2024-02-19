import 'dart:typed_data';

abstract class Message
{
  int type;
  DateTime time = DateTime.now();

  Message(this.type);

  void parse(Uint8List message);
}