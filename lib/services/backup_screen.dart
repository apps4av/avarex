import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/map_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/universal_io.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  static String getUserDataJsonPath() {
    final storageRef = FirebaseStorage.instance.ref();
    final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child("user.json");
    final bucket = FirebaseStorage.instance.app.options.storageBucket;
    final fullPath = dbRef.fullPath;
    return 'gs://$bucket/$fullPath';
  }

  static String getAircraftPath() {
    final storageRef = FirebaseStorage.instance.ref();
    final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child("aircraft.pdf");
    final bucket = FirebaseStorage.instance.app.options.storageBucket;
    final fullPath = dbRef.fullPath;
    return 'gs://$bucket/$fullPath';
  }

  static String getUserTracksPath() {
    final storageRef = FirebaseStorage.instance.ref();
    final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child("tracks.kml");
    final bucket = FirebaseStorage.instance.app.options.storageBucket;
    final fullPath = dbRef.fullPath;
    return 'gs://$bucket/$fullPath';
  }

  @override
  BackupScreenState createState() => BackupScreenState();
}

class BackupScreenState extends State<BackupScreen> {

  final storageRef = FirebaseStorage.instance.ref();
  String _status = "";

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

    final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child("user.db");

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
                  final storageRef = FirebaseStorage.instance.ref();
                  final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child("user.json");
                  final md = SettableMetadata(
                    contentType: "text/plain",
                  );
                  dbRef.putString(await UserDatabaseHelper.db.getLogbookAsJson(), metadata: md).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (mounted) {
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
            subtitle: const Text("Prepare and send aircraft manual (PDF only)"),
            trailing: IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () async {
                try {
                  final storageRef = FirebaseStorage.instance.ref();
                  final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child("aircraft.pdf");
                  final md = SettableMetadata(
                    contentType: "application/pdf",
                  );
                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', "PDF"]);
                  String? path = result!.files.single.path;
                  File file = File(path!);

                  dbRef.putFile(file, md).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (mounted) {
                    MapScreenState.showToast(context, "Operation Failed",
                        Icon(Icons.warning, color: Colors.red,), 3);
                  }
                }
              },
            ),
          ),
          ListTile(
            enabled: _status.isEmpty || _status == "Completed" || _status == "Operation failed" || _status == "Canceled",
            title: const Text("Flight Intelligence - Tracks"),
            subtitle: const Text("Prepare and send recorded tracks (KML only)"),
            trailing: IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () async {
                try {
                  final storageRef = FirebaseStorage.instance.ref();
                  final dbRef = storageRef.child("users/").child(FirebaseAuth.instance.currentUser!.uid).child("tracks.kml");
                  final md = SettableMetadata(
                    contentType: "text/plain",
                  );
                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['kml', "KML"]);
                  String? path = result!.files.single.path;
                  File file = File(path!);

                  dbRef.putFile(file, md).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (mounted) {
                    MapScreenState.showToast(context, "Operation Failed",
                        Icon(Icons.warning, color: Colors.red,), 3);
                  }
                }
              },
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
                  dbRef.putFile(dbFile).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (mounted) {
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
                  dbRef.writeToFile(dbFile).snapshotEvents.listen((taskSnapshot) {
                    if(mounted) {
                      setState(() {
                        setStatus(taskSnapshot);
                      });
                    }
                  });
                }
                catch(e) {
                  if (mounted) {
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
