import 'package:universal_io/universal_io.dart';

class ZipException {

}

class ZipFileReaderSync {
  void open(File f) {}
  void close() {}
  void readToFile (String name, File file) {}
  List<ZipEntry> entries() {
    return [];
  }
}

class ZipEntry {
  bool get isDir => false;
  String get name => "";
}