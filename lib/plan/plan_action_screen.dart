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

    Widget loadSavePage = const PlanLoadSaveWidget();

    Widget createPage = const PlanCreateWidget();

    Widget filePage = const PlanFileWidget();

    Widget managePage = const PlanManageWidget();

    Widget transferPage = const PlanTransferWidget();

    List<Widget> pages = [];
    pages.add(loadSavePage);
    pages.add(createPage);
    pages.add(filePage);
    pages.add(managePage);
    if (Constants.shouldShowBluetoothSpp) {
      pages.add(transferPage);
    }

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
          Expanded(flex: 8, child: Padding(padding: const EdgeInsets.all(10), child: pages[_current])),
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisAlignment: MainAxisAlignment.end, children:[
            TextButton(
                style: _current == 0 ? TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ) : null,
                child: const Text("Load & Save"),
                onPressed: () => setState(() {
                  _current = 0;
                })
            ),
            TextButton(
                style: _current == 1 ? TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ) : null,
                child: const Text("Create"),
                onPressed: () => setState(() {
                  _current = 1;
                })
            ),
            TextButton(
                style: _current == 2 ? TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ) : null,
                child: const Text("Brief & File"),
                onPressed: () => setState(() {
                  _current = 2;
                })
            ),
            TextButton(
                style: _current == 3 ? TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ) : null,
                child: const Text("Manage"),
                onPressed: () => setState(() {
                  _current = 3;
                })
            ),
            if (Constants.shouldShowBluetoothSpp)
              TextButton(
                style: _current == 4 ? TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ) : null,
                child: const Text("Transfer"),
                onPressed: () => setState(() {
                  _current = 4;
                })
            ),
          ])),
          ),
        ],
        )
    );
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
