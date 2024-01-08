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
    return
      Column(
        children: [
          const Row(
            children: [
              Expanded(flex: 1, child: Text("Dist")),
              Expanded(flex: 1, child: Text("Hdng")),
              Expanded(flex: 1, child: Text("Time")),
              Expanded(flex: 1, child: Text("Altd")),
              Expanded(flex: 1, child: Text("Fuel")),
          ]),
          Row(
            children: [
              Expanded(flex: 1, child: Text("---")),
              Expanded(flex: 1, child: Text("---")),
              Expanded(flex: 1, child: Text("--:--")),
              Expanded(flex: 1, child: Text("-----")),
              Expanded(flex: 1, child: Text("---")),
          ]),
        ]
      );

  }

}
