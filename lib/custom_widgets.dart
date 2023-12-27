import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';

import 'constants.dart';

class CustomWidgets {
  static Widget dropDownButton(BuildContext context, String defaultValue, List<String> items, Alignment align, double bottom, Function (String?) onChange) {
    return Positioned(
        child: Align(
            alignment: align,
            child: items[0].isEmpty ? Container() : Container(
                padding: EdgeInsets.fromLTRB(5, 5, 5, bottom),
                child:DropdownButtonHideUnderline(
                    child:DropdownButton2<String>( // airport selection
                    buttonStyleData: ButtonStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                    ),
                    isExpanded: false,
                    value: defaultValue,
                    items: items.map((String item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(item)
                      );
                    }).toList(),
                    onChanged: (value) {
                      onChange(value);
                    },
                    )
                )
            )
        )
    );
  }

  static Widget centerButton(BuildContext context, double bottom, Function() pressed) {
    return Positioned(
      child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 0, 0, bottom),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Constants.centerButtonBackgroundColor,
                padding: const EdgeInsets.all(5.0),
              ),
              onPressed: () {
                pressed();
              },
              child: const Text("Center"),
          ))
      ),
    );
  }
}