import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/utils/toast.dart';
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
  double _progress = 0;
  bool _isUploading = false;
  bool _isDownloading = false;
  bool _confirmingBackup = false;
  bool _confirmingRestore = false;

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

  void _setStatus(TaskSnapshot snapshot) {
    switch (snapshot.state) {
      case TaskState.running:
        if (snapshot.bytesTransferred > 0 && snapshot.totalBytes > 0) {
          _progress = snapshot.bytesTransferred / snapshot.totalBytes;
          _status = "${(_progress * 100).round()}%";
        }
        break;
      case TaskState.success:
        Toast.showToast(context, "Operation Completed", const Icon(Icons.check_circle, color: Colors.green), 3);
        _status = "";
        _progress = 0;
        _isUploading = false;
        _isDownloading = false;
        break;
      case TaskState.paused:
        break;
      case TaskState.canceled:
      case TaskState.error:
        Toast.showToast(context, "Operation Failed", const Icon(Icons.error, color: Colors.red), 3);
        _status = "";
        _progress = 0;
        _isUploading = false;
        _isDownloading = false;
        break;
    }
  }

  bool get _isBusy => _isUploading || _isDownloading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Row(
          children: [
            Icon(Icons.cloud_sync, size: 24),
            SizedBox(width: 8),
            Text("Backup & Sync"),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.cloud_done, size: 32, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Cloud Storage",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Keep your data safe and synced across devices",
                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            if (_isBusy) ...[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              value: _progress > 0 ? _progress : null,
                              strokeWidth: 3,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isUploading ? "Uploading..." : "Downloading...",
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                if (_status.isNotEmpty)
                                  Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_progress > 0) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _progress, borderRadius: BorderRadius.circular(4)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                "ACTIONS",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1,
                ),
              ),
            ),
            
            _buildBackupCard(),
            
            const SizedBox(height: 8),
            
            _buildRestoreCard(),
            
            const SizedBox(height: 24),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                "WHAT GETS BACKED UP",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1,
                ),
              ),
            ),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _backupItem(Icons.flight, "Aircraft profiles"),
                    const SizedBox(height: 12),
                    _backupItem(Icons.book, "Logbook entries"),
                    const SizedBox(height: 12),
                    _backupItem(Icons.checklist, "Checklists"),
                    const SizedBox(height: 12),
                    _backupItem(Icons.balance, "Weight & balance data"),
                    const SizedBox(height: 12),
                    _backupItem(Icons.route, "Plans"),
                    const SizedBox(height: 12),
                    _backupItem(Icons.settings, "Settings"),
                    const SizedBox(height: 12),
                    _backupItem(Icons.history, "AI chat history"),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Your data is securely stored in the cloud and linked to your account.",
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            enabled: !_isBusy && !_confirmingRestore,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud_upload, color: Colors.blue),
            ),
            title: const Text("Backup to Cloud", style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text("Upload your local data to secure cloud storage"),
            trailing: _isUploading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_confirmingBackup ? Icons.expand_less : Icons.chevron_right),
            onTap: !_isBusy && !_confirmingRestore ? () {
              setState(() {
                _confirmingBackup = !_confirmingBackup;
                _confirmingRestore = false;
              });
            } : null,
          ),
          if (_confirmingBackup)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              color: Colors.blue.withAlpha(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "This will overwrite any existing cloud backup.",
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _confirmingBackup = false),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() => _confirmingBackup = false);
                          _performBackup();
                        },
                        icon: const Icon(Icons.cloud_upload, size: 18),
                        label: const Text("Backup Now"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRestoreCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            enabled: !_isBusy && !_confirmingBackup,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud_download, color: Colors.green),
            ),
            title: const Text("Restore from Cloud", style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text("Download and restore your data from cloud backup"),
            trailing: _isDownloading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_confirmingRestore ? Icons.expand_less : Icons.chevron_right),
            onTap: !_isBusy && !_confirmingBackup ? () {
              setState(() {
                _confirmingRestore = !_confirmingRestore;
                _confirmingBackup = false;
              });
            } : null,
          ),
          if (_confirmingRestore)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              color: Colors.orange.withAlpha(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "This will overwrite your local data. Any changes not backed up will be lost.",
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _confirmingRestore = false),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() => _confirmingRestore = false);
                          _performRestore();
                        },
                        icon: const Icon(Icons.cloud_download, size: 18),
                        label: const Text("Restore Now"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _backupItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(label),
        const Spacer(),
        Icon(Icons.check_circle, size: 18, color: Colors.green.withAlpha(180)),
      ],
    );
  }

  Future<void> _performBackup() async {
    final dbFile = File(UserDatabaseHelper.getPath());
    try {
      setState(() {
        _isUploading = true;
        _progress = 0;
      });
      
      files[dbRefUserDb]!.putFile(dbFile).snapshotEvents.listen((taskSnapshot) {
        if (mounted) {
          setState(() {
            _setStatus(taskSnapshot);
          });
        }
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
        _progress = 0;
      });
      if (mounted) {
        Toast.showToast(context, "Backup Failed", const Icon(Icons.error, color: Colors.red), 3);
      }
    }
  }

  Future<void> _performRestore() async {
    final dbFile = File(UserDatabaseHelper.getPath());
    try {
      setState(() {
        _isDownloading = true;
        _progress = 0;
      });
      
      files[dbRefUserDb]!.writeToFile(dbFile).snapshotEvents.listen((taskSnapshot) {
        if (mounted) {
          setState(() {
            _setStatus(taskSnapshot);
          });
        }
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _progress = 0;
      });
      if (mounted) {
        Toast.showToast(context, "Restore Failed", const Icon(Icons.error, color: Colors.red), 3);
      }
    }
  }
}
