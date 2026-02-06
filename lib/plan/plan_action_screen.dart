import 'package:avaremp/constants.dart';
import 'package:avaremp/plan/plan_create_widget.dart';
import 'package:avaremp/plan/plan_file_widget.dart';
import 'package:avaremp/plan/plan_load_save_widget.dart';
import 'package:avaremp/plan/plan_manage_widget.dart';
import 'package:avaremp/plan/plan_transfer_widget.dart';
import 'package:flutter/material.dart';

class PlanActionScreen extends StatefulWidget {
  const PlanActionScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlanActionState();
}

class PlanActionState extends State<PlanActionScreen> {

  int _current = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _makeContent() {

    final tabs = _buildTabs();
    final current = _current >= tabs.length ? 0 : _current;

    return Container(
        padding: const EdgeInsets.all(5),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        child:
        Column(children: [
          // various info
          Expanded(
              flex: 8,
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: tabs[current].page)),
          // add various buttons that expand to diagram
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisAlignment: MainAxisAlignment.end, children:[
            for (int index = 0; index < tabs.length; index++)
              TextButton(
                  child: Text(tabs[index].label),
                  onPressed: () => setState(() {
                        _current = index;
                      }))
          ])),
          ),
        ],
        )
    );
  }

  List<_PlanActionTab> _buildTabs() {
    final tabs = <_PlanActionTab>[
      _PlanActionTab(
          label: "Load & Save", page: const PlanLoadSaveWidget()),
      _PlanActionTab(label: "Create", page: const PlanCreateWidget()),
      _PlanActionTab(label: "Brief & File", page: const PlanFileWidget()),
      _PlanActionTab(label: "Manage", page: const PlanManageWidget()),
    ];

    if (Constants.shouldShowBluetoothSpp) {
      tabs.add(_PlanActionTab(
          label: "Transfer", page: const PlanTransferWidget()));
    }

    return tabs;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      title: const Text("Plan Actions"),
    ),
    body: _makeContent());
  }
}

class _PlanActionTab {
  final String label;
  final Widget page;

  const _PlanActionTab({required this.label, required this.page});
}