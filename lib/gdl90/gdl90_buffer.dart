import 'dart:typed_data';


class Gdl90Buffer {

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

    // find 0x7e to 0x7e
    // start
    int start = _buffer.indexWhere((element) => element == 0x7e);
    if(start == -1) {
      return null;
    }
    int end = _buffer.indexWhere((element) => element == 0x7e, start + 1);
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