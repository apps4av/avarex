import 'package:flutter/material.dart';
import 'csup.dart';
import 'draw_canvas.dart';
import 'find.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int mSelectedIndex = 0; // for various tab screens
  List<String> charts = ["Sectional", "TAC", "WAC"];
  String chartSelectedValue = "Sectional";

  // define tabs here
  static final List<Widget> _widgetOptions = <Widget>[
    const DrawCanvas(),
    const CSup(),
    const DrawCanvas(),
  ];

  void mOnItemTapped(int index) {
    setState(() {
      mSelectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.settings), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () => Navigator.pushNamed(context, '/settings')),
        actions: [
          IconButton(icon: const Icon(Icons.download), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () => Navigator.pushNamed(context, '/download')),
          DropdownButton<String>( // chart selection
            value: chartSelectedValue,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            items: charts.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                chartSelectedValue = val ?? charts[0];
              });
            },
          ),
          IconButton(icon: const Icon(Icons.search), padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), onPressed: () { showSearch(context: context, delegate: Find()); },),
        ],
        backgroundColor: Colors.blueAccent,
      ),
      body: Center(
        child: _widgetOptions.elementAt(mSelectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'MAP',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            label: 'CSUP',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book),
            label: 'PLATE',
          ),
        ],
        currentIndex: mSelectedIndex,
        onTap: mOnItemTapped,
      ),
    );
  }
}

