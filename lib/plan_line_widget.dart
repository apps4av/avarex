import 'package:flutter/material.dart';

class PlanLineWidget extends StatefulWidget {

  // it crashes if not static

  const PlanLineWidget({super.key, });

  @override
  State<StatefulWidget> createState() => PlanLineWidgetState();
}

class PlanLineWidgetState extends State<PlanLineWidget> {

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          getNullFields()
        ]
      );
  }

  static Widget getHeading() {
    return const Row(children: [
      Expanded(flex: 1, child: Text("Dist")),
      Expanded(flex: 1, child: Text("Hdng")),
      Expanded(flex: 1, child: Text("Time")),
      Expanded(flex: 1, child: Text("Alt")),
      Expanded(flex: 1, child: Text("Fuel")),
    ]);
  }

  static Widget getNullFields() {
    return const Row(children: [
    Expanded(flex: 1, child: Text("---")),
    Expanded(flex: 1, child: Text("---")),
    Expanded(flex: 1, child: Text("--:--")),
    Expanded(flex: 1, child: Text("-----")),
    Expanded(flex: 1, child: Text("---")),
    ]);
  }

}
