import 'package:avaremp/services/app_notice.dart';
import 'package:avaremp/services/app_notice_service.dart';
import 'package:flutter/material.dart';

import '../constants.dart';

/// Apps4Av messages saved on this device until the pilot deletes one.
class AppNoticesScreen extends StatefulWidget {
  const AppNoticesScreen({super.key});

  @override
  State<AppNoticesScreen> createState() => _AppNoticesScreenState();
}

class _AppNoticesScreenState extends State<AppNoticesScreen> {
  late List<StoredAppNotice> _notices;

  @override
  void initState() {
    super.initState();
    _notices = AppNoticeService.instance.saved();
  }

  void _delete(StoredAppNotice notice) {
    AppNoticeService.instance.deleteSaved(notice);
    setState(() {
      _notices = AppNoticeService.instance.saved();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Messages"),
      ),
      body: _notices.isEmpty
          ? const Center(child: Text("No messages"))
          : ListView.separated(
              itemCount: _notices.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final StoredAppNotice notice = _notices[index];
                return Dismissible(
                  key: ValueKey(notice.dismissKey),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    color: scheme.errorContainer,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete_outline,
                        color: scheme.onErrorContainer),
                  ),
                  onDismissed: (_) => _delete(notice),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          notice.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(notice.body),
                        if (notice.url != null) ...[
                          const SizedBox(height: 8),
                          SelectableText(
                            notice.url!,
                            style: TextStyle(color: scheme.primary),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
