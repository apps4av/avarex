import 'dart:typed_data';


class NmeaBuffer {

  static const _maxLength = 65536;
  final List<int> _buffer = List.empty(growable: true);

  // not thread safe
  void put(Uint8List data) {
    if(_buffer.length > _maxLength) {
      _buffer.clear(); // this should not happen
      return;
    }
    _buffer.addAll(data);
  }
  
  Uint8List? get() {

    // find $ to LF
    // start
    int start = _buffer.indexWhere((element) => element == 0x24);
    if(start == -1) {
      return null;
    }

    // skip all $ that follow start
    while(_buffer[start] == 0x24) {
      start++;
      if(start == _buffer.length) {
        return null;
      }
    }
    start--; //keep $

    int end = _buffer.indexWhere((element) => element == 0x0a, start);
    if(end == -1) {
      return null;
    }

    Iterable<int> range = _buffer.getRange(start, end + 1);
    Uint8List data = Uint8List.fromList(range.toList());

    // 0 means remove leading garbage if any
    _buffer.removeRange(0, end + 1);

    return data;
  }
}