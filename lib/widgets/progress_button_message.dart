import 'package:flutter/material.dart';

class ProgressButtonMessage extends StatefulWidget {

  final String label;
  final String title;
  final String success;
  final List<String> args;
  final Future<String> Function(List<String> args) onPressed;
  final void Function(bool)? onComplete;

  const ProgressButtonMessage(this.label, this.title, this.onPressed,  this.args, this.onComplete, this.success, {super.key});

  @override
  State<StatefulWidget> createState() => ProgressButtonMessageState();

}


class ProgressButtonMessageState extends State<ProgressButtonMessage> {
  bool progress = false;
  String error = "";
  Color color = Colors.red;

  @override
  Widget build(BuildContext context) {

    return Padding(padding: const EdgeInsets.all(10), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[

        Text(widget.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        Row(
          children: <Widget>[
            TextButton(onPressed: () {
              setState(() {
                error = "";
                progress = true;
                widget.onPressed(widget.args).then((value) {
                  setState(() {
                    progress = false;
                    error = value;
                    if(error.isEmpty) {
                      color = Colors.green;
                      error = widget.success;
                    }
                    if(widget.onComplete != null) {
                      widget.onComplete!(value.isEmpty);
                    }
                  });
                });
              });
            }, child: Text(widget.title)),
            Visibility(visible: progress, child: const CircularProgressIndicator(),),
          ],
        ),
        Text(error, style: TextStyle(color: color),),
      ],
    ));
  }

}
