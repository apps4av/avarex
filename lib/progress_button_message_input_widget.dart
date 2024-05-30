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
  final void Function(bool, String, String)? onComplete;

  const ProgressButtonMessageInputWidget(this.label, this.label1, this.init1, this.label2, this.init2, this.title, this.onPressed,  this.onComplete, this.success, {super.key});

  @override
  State<StatefulWidget> createState() => ProgressButtonMessageInputWidgetState();

}

class ProgressButtonMessageInputWidgetState extends State<ProgressButtonMessageInputWidget> {

  bool progress = false;
  String error = "";
  Color color = Colors.red;

  @override
  Widget build(BuildContext context) {
    String input1 = widget.init1;
    String input2 = widget.init2;

    return Padding(padding: const EdgeInsets.all(10), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[

        Text(widget.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),),

        TextFormField(
          onChanged: (value) {
            input1 = value;
          },
          controller: TextEditingController()..text = widget.init1,
          decoration: InputDecoration(border: const UnderlineInputBorder(), labelText: widget.label1)
        ),

        TextFormField(
          obscureText: true,
          onChanged: (value) {
           input2 = value;
          },
          controller: TextEditingController()..text = widget.init2,
          decoration: InputDecoration(border: const UnderlineInputBorder(), labelText: widget.label2)
        ),

        Row(
          children: <Widget>[
            TextButton(onPressed: () {
              setState(() {
                error = "";
                progress = true;
                widget.onPressed([input1, input2]).then((value) {
                  setState(() {
                    progress = false;
                    error = value;
                    if(error.isEmpty) {
                      color = Colors.green;
                      error = widget.success;
                    }
                    if(widget.onComplete != null) {
                      // return success and new values
                      widget.onComplete!(value.isEmpty, input1, input2);
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
