import 'package:flutter/material.dart';

class ProgressButtonMessageWidget extends StatefulWidget {

  final String label;
  final String title;
  final String success;
  final List<String> args;
  final Future<String> Function(List<String> args) onPressed;
  final void Function(bool)? onComplete;

  bool progress = false;
  String error = "";
  Color color = Colors.red;

  ProgressButtonMessageWidget(this.label, this.title, this.onPressed,  this.args, this.onComplete, this.success, {super.key});

  @override
  State<StatefulWidget> createState() => ProgressButtonMessageWidgetState();

}


class ProgressButtonMessageWidgetState extends State<ProgressButtonMessageWidget> {

  @override
  Widget build(BuildContext context) {

    return Padding(padding: const EdgeInsets.all(10), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[

        Text(widget.label, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 18),),
        Row(
          children: <Widget>[
            TextButton(onPressed: () {
              setState(() {
                widget.error = "";
                widget.progress = true;
                widget.onPressed(widget.args).then((value) {
                  setState(() {
                    widget.progress = false;
                    widget.error = value;
                    if(widget.error.isEmpty) {
                      widget.color = Colors.green;
                      widget.error = widget.success;
                    }
                    if(widget.onComplete != null) {
                      widget.onComplete!(value.isEmpty);
                    }
                  });
                });
              });
            }, child: Text(widget.title)),
            Visibility(visible: widget.progress, child: const CircularProgressIndicator(),),
          ],
        ),
        Text(widget.error, style: TextStyle(color: widget.color),),
      ],
    ));
  }

}
