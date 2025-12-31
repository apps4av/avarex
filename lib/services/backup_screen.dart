import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/toast.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
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

  Map<String, Reference?> files = {
    dbRefUserDb: null,
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
          Toast.showToast(context, "Operation Completed",
              Icon(Icons.info, color: Colors.green,), 3);
          _status = "";
          break;
        case TaskState.paused:
          break;
        case TaskState.canceled:
        case TaskState.error:
          Toast.showToast(context, "Operation Failed",
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
                    Toast.showToast(context, "Operation Failed",
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
                    Toast.showToast(context, "Operation Failed",
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
