import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:universal_io/universal_io.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  BackupScreenState createState() => BackupScreenState();
}

class BackupScreenState extends State<BackupScreen> {

  final storageRef = FirebaseStorage.instance.ref();
  String _status = "";

  static final String dbRefUserDb = "user.db";
  static final String dbRefLogbook = "logbook.json";
  static final String dbRefPlan = "plan.json";
  static final String dbRefPoh = "poh.pdf";

  Map<String, Reference?> files = {
    dbRefUserDb: null,
    dbRefLogbook: null,
    dbRefPlan: null,
    dbRefPoh: null,
  };

  static String getPath(String key) {
    final storageRef = FirebaseStorage.instance.ref();
    final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child(key);
    final bucket = FirebaseStorage.instance.app.options.storageBucket;
    final fullPath = dbRef.fullPath;
    return 'gs://$bucket/$fullPath';
  }

  static Future<List<String>> getFileList() async {
    List<String> fileList = [];
    final storageRef = FirebaseStorage.instance.ref();
    final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid);
    final bucket = FirebaseStorage.instance.app.options.storageBucket;
    await dbRef.listAll().then((listResult) {
      for (var item in listResult.items) {
        final fullPath = item.fullPath;
        fileList.add('gs://$bucket/$fullPath');
      }
    });
    return fileList;
  }

  @override
  void initState() {
    super.initState();
    for (var key in files.keys) {
      files[key] = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child(key);
    }
  }

  Future<bool> showConfirmDialog(String message) {
    // return a Future that resolves to true if user confirms, false otherwise
    Future<dynamic> confirmed = showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Warning!"),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text("No"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text("Yes"),
              onPressed: () {
                Navigator.of(context).pop(true);
                // proceed with restore
              },
            ),
          ],
        );
      },
    );

    return confirmed.then((value) => value == true);
  }

  @override
  Widget build(BuildContext context) {

    void setStatus(TaskSnapshot snapshot) {
      switch (snapshot.state) {
        case TaskState.running:
          _status = (snapshot.bytesTransferred > 0 && snapshot.totalBytes > 0) ? "${((snapshot.bytesTransferred / snapshot.totalBytes) * 100).round()}%" : "";
          break;
        case TaskState.success:
          MapScreenState.showToast(context, "Operation Completed",
              Icon(Icons.info, color: Colors.green,), 3);
          _status = "";
          break;
        case TaskState.paused:
          break;
        case TaskState.canceled:
        case TaskState.error:
          MapScreenState.showToast(context, "Operation Failed",
              Icon(Icons.warning, color: Colors.red,), 3);
          _status = "";
          break;
      }

    }

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: const Text("Backup/Sync"),
            actions: [Padding(padding: EdgeInsets.all(10), child: Text(_status)),
            ],
        ),
        body: Column(children: [
          ListTile(
            enabled: _status.isEmpty || _status == "Completed" || _status == "Operation failed" || _status == "Canceled",
            title: const Text("Flight Intelligence - Log book"),
            subtitle: const Text("Prepare and send your log book data"),
            trailing: IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () async {
                try {
                  final md = SettableMetadata(
                    contentType: "text/plain",
                  );
                  files[dbRefLogbook]!.putString(await UserDatabaseHelper.db.getLogbookAsJson(), metadata: md).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (context.mounted) {
                    MapScreenState.showToast(context, "Operation Failed",
                        Icon(Icons.warning, color: Colors.red,), 3);
                  }
                }
              },
            ),
          ),
          ListTile(
            enabled: _status.isEmpty || _status == "Completed" || _status == "Operation failed" || _status == "Canceled",
            title: const Text("Flight Intelligence - Aircraft"),
            subtitle: const Text("Prepare and send POH (PDF only)"),
            trailing: IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () async {
                try {
                  final md = SettableMetadata(
                    contentType: "application/pdf",
                  );
                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', "PDF"]);
                  String? path = result!.files.single.path;
                  File file = File(path!);

                  files[dbRefPoh]!.putFile(file, md).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (context.mounted) {
                    MapScreenState.showToast(context, "Operation Failed",
                        Icon(Icons.warning, color: Colors.red,), 3);
                  }
                }
              },
            ),
          ),
          ListTile(
            enabled: _status.isEmpty || _status == "Completed" || _status == "Operation failed" || _status == "Canceled",
            title: const Text("Flight Intelligence - Plan"),
            subtitle: const Text("Prepare and send your current plan and weather"),
            trailing: IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () async {
                try {
                  final md = SettableMetadata(
                    contentType: "text/plain",
                  );

                  PlanRoute route = Storage().route;


                  String data = "";
                  if(route.isNotEmpty) {
                    data += "Plan is: ${route.toString()}\n";
                    // winds
                    LatLng start = route.getAllDestinations().first.coordinate;
                    LatLng end = route.getAllDestinations().last.coordinate;
                    String? windsStart = WindsCache.getWindsAtAll(start, 6);
                    String? windsEnd = WindsCache.getWindsAtAll(end, 6);
                    if(windsStart != null) {
                      data += "Winds at departure:\n$windsStart\n";
                    }
                    if(windsEnd != null) {
                      data += "Winds at destination:\n$windsStart\n";
                    }
                  }
                  files[dbRefPlan]!.putString(data, metadata: md).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (context.mounted) {
                    MapScreenState.showToast(context, "Operation Failed $e",
                        Icon(Icons.warning, color: Colors.red,), 3);
                  }
                }
              },
            ),
          ),

          ListTile(
            enabled: _status.isEmpty || _status == "Completed" || _status == "Operation failed" || _status == "Canceled",
            title: const Text("Flight Intelligence - Delete"),
            subtitle: const Text("Delete all Flight Intelligence data"),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                // download database file
                  int count = 1;
                  int total = files.length;
                  final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid);
                  await dbRef.listAll().then((listResult) {
                    for (var item in listResult.items) {
                      if(item.fullPath.endsWith(".pdf") || item.fullPath.endsWith(".json")) {
                        try {
                          item.delete();
                        }
                        catch (e) {
                          if (context.mounted) {
                            MapScreenState.showToast(
                                context, "Operation Failed",
                                Icon(Icons.warning, color: Colors.red,), 3);
                          }
                        }
                        setState(() {
                          _status = "${count++}/$total";
                        });
                      }
                    }
                  });
                  if (context.mounted) {
                    MapScreenState.showToast(context, "Operation Completed",
                        Icon(Icons.info, color: Colors.green,), 3);
                  }
                  setState(() {
                    _status = "";
                  });
                }
            ),
          ),

          Divider(),
          ListTile(
            enabled: _status.isEmpty || _status == "Completed" || _status == "Operation failed" || _status == "Canceled",
            title: const Text("Backup"),
            subtitle: const Text("Backup your data to cloud storage"),
            trailing: IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () async {
                final dbFile = File(UserDatabaseHelper.getPath());
                bool proceed = await showConfirmDialog("This operation will overwrite your existing cloud backup. Do you want to continue?");
                if(!proceed) {
                  return;
                }
                try {
                  files[dbRefUserDb]!.putFile(dbFile).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (context.mounted) {
                    MapScreenState.showToast(context, "Operation Failed",
                        Icon(Icons.warning, color: Colors.red,), 3);
                  }
                }
              },
            ),
          ),
          ListTile(
            enabled: _status.isEmpty || _status == "Completed" || _status == "Operation failed" || _status == "Canceled",
            title: const Text("Restore"),
            subtitle: const Text("Restore your data from cloud storage"),
            trailing: IconButton(
              icon: const Icon(Icons.download),
              onPressed: () async {
                // download database file
                final dbFile = File(UserDatabaseHelper.getPath());
                bool proceed = await showConfirmDialog("This operation will overwrite your existing local data. Do you want to continue?");
                if(!proceed) {
                  return;
                }
                try {
                  files[dbRefUserDb]!.writeToFile(dbFile).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (context.mounted) {
                    MapScreenState.showToast(context, "Operation Failed",
                        Icon(Icons.warning, color: Colors.red,), 3);
                  }
                }
              },
            ),
          ),
        ],)
    );
  }
}
