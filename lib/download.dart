import 'dart:core';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';

class Download {

  static String cycle = "2311";

  void unzip(String dirname, String filename) async {
    final inputStream = InputFileStream(filename);
    final archive = ZipDecoder().decodeBuffer(inputStream);
    extractArchiveToDisk(archive, dirname);
  }

  void deleteZipFile(File file) async {
    try {
      await file.delete();
    }
    catch (e) {
      debugger(message: "Unable to delete the zip file");
    }
  }

  void downloadFile(String filename) async {
    Directory dir = await getApplicationDocumentsDirectory();
    File file = File("${dir.path}/$filename.zip");
    deleteZipFile(file);

    HttpClient client = HttpClient();
    var request = await client.getUrl(Uri.parse("https://apps4av.org/new/$cycle/$filename.zip"));
    var response = await request.close();
    var bytes = await consolidateHttpClientResponseBytes(response);
    await file.writeAsBytes(bytes);

    // unzip
    unzip(dir.path, file.path);
    deleteZipFile(file);

  }
}