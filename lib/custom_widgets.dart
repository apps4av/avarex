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
                        child: Text(item, style: TextStyle(fontSize: Constants.dropDownButtonFontSize))
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

}