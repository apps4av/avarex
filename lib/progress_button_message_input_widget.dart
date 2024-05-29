import 'package:flutter/material.dart';

class ProgressButtonMessageInputWidget extends StatefulWidget {

  final String label;
  final String label1;
  final String label2;
  final String init1;
  final String init2;
  final String title;
  final String success;
  final Future<String> Function(List<String> args) onPressed;
  final void Function(bool)? onComplete;

  bool progress = false;
  String error = "";
  Color color = Colors.red;
  String input1 = "";
  String input2 = "";

  ProgressButtonMessageInputWidget(this.label, this.label1, this.init1, this.label2, this.init2, this.title, this.onPressed,  this.onComplete, this.success, {super.key}) {
    input1 = init1;
    input2 = init2;
  }

  @override
  State<StatefulWidget> createState() => ProgressButtonMessageInputWidgetState();

}


class ProgressButtonMessageInputWidgetState extends State<ProgressButtonMessageInputWidget> {

  @override
  Widget build(BuildContext context) {

    return Padding(padding: const EdgeInsets.all(10), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[

        Text(widget.label, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 18),),

        TextFormField(
          onChanged: (value) {
            widget.input1 = value;
          },
          controller: TextEditingController()..text = widget.init1,
          decoration: InputDecoration(border: const UnderlineInputBorder(), labelText: widget.label1)
        ),

        TextFormField(
          obscureText: true,
          onChanged: (value) {
            widget.input2 = value;
          },
          controller: TextEditingController()..text = widget.init2,
          decoration: InputDecoration(border: const UnderlineInputBorder(), labelText: widget.label2)
        ),

        Row(
          children: <Widget>[
            TextButton(onPressed: () {
              setState(() {
                widget.error = "";
                widget.progress = true;
                widget.onPressed([widget.input1, widget.input2]).then((value) {
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
