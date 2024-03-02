
class NmeaMessage {

  String type;
  DateTime time;

  NmeaMessage(this.type) : time = DateTime.now();

  void parse(String data) {

  }

}