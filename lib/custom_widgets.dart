import 'package:flutter/material.dart';

class CustomWidgets {
  static Widget dropDownButton(BuildContext context, String defaultValue, List<String> items, Alignment align, double bottom, Function (String?) onChange) {
    return Positioned(
        child: Align(
            alignment: align,
            child: items[0].isEmpty ? Container() :
            DropdownButton<String>( // airport selection
              padding: EdgeInsets.fromLTRB(5, 5, 5, bottom),
              underline: Container(),
              iconEnabledColor: Colors.transparent,
              value: defaultValue,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, style: TextStyle(color: Colors.cyanAccent, backgroundColor: Theme.of(context).dialogBackgroundColor.withAlpha(156))),
                );
              }).toList(),
              onChanged: (value) {
                onChange(value);
              },
            )
        )
    );
  }

  static Widget centerButton(BuildContext context, double bottom, Function() pressed) {
    return Positioned(
      child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 0, 0, bottom + 40),
            child: CircleAvatar(backgroundColor: Theme.of(context).dialogBackgroundColor.withAlpha(156), child:IconButton(
            onPressed: () {
              pressed();
            }, icon: const Icon(Icons.gps_fixed)),
          ))
      ),
    );
  }
}