import 'package:flutter/material.dart';
import '../basic/commons.dart';
import 'init_screen.dart';

class CalculatorScreen extends StatelessWidget {
  const CalculatorScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          padding: const EdgeInsets.only(top: 10.0, left: 10.0),
          color: Colors.black,
          child: const ContentBody(),
        ),
      );
}

class ContentBody extends StatefulWidget {
  const ContentBody({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => ContentBodyState();
}

class ContentBodyState extends State<ContentBody> {
  String sums = '0';
  String total = '0';
  String flag = '';
  int tag = 0;
  List list = [
    {'bgc': '0xFFFF9800', 'color': '0xFFFFFFFF'},
    {'bgc': '0xFFFF9800', 'color': '0xFFFFFFFF'},
    {'bgc': '0xFFFF9800', 'color': '0xFFFFFFFF'},
    {'bgc': '0xFFFF9800', 'color': '0xFFFFFFFF'},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(child: Container()),
        Container(
          padding: const EdgeInsets.only(
              top: 10.0, left: 10.0, right: 20.0, bottom: 10.0),
          child: Container(
            alignment: Alignment.bottomRight,
            child: Text(
              sums,
              maxLines: 8,
              style: const TextStyle(fontSize: 33, color: Colors.white),
            ),
          ),
        ),
        Expanded(child: Container()),
        Column(
          children: [
            Center(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(32),
                        color: Colors.grey,
                        splashColor: Colors.white,
                        onPressed: () {
                          btnclick('重置');
                        },
                        child: const Text('AC',
                            style:
                                TextStyle(color: Colors.black, fontSize: 20)),
                        shape: const CircleBorder(
                          side: BorderSide(color: Colors.grey),
                        ),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(32),
                        color: Colors.grey,
                        splashColor: Colors.white,
                        onPressed: () {
                          btnclick('加/减');
                        },
                        child: const Text('+/-',
                            style:
                                TextStyle(color: Colors.black, fontSize: 20)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Colors.grey)),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(32),
                        color: Colors.grey,
                        splashColor: Colors.white,
                        onPressed: () {
                          btnclick('百分号');
                        },
                        child: const Text('%',
                            style:
                                TextStyle(color: Colors.black, fontSize: 25)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Colors.grey)),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(24),
                        color: Color(int.parse(list[0]['bgc'])),
                        splashColor: Color(int.parse(list[0]['bgc'])),
                        onPressed: () {
                          btnclick('除');
                        },
                        child: Text('÷',
                            style: TextStyle(
                                color: Color(int.parse(list[0]['color'])),
                                fontSize: 30)),
                        shape: CircleBorder(
                            side: BorderSide(
                                color: Color(int.parse(list[0]['bgc'])))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                ],
              ),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('7');
                        },
                        child: const Text('7',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('8');
                        },
                        child: const Text('8',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('9');
                        },
                        child: const Text('9',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(24),
                        color: Color(int.parse(list[1]['bgc'])),
                        splashColor: Color(int.parse(list[1]['bgc'])),
                        onPressed: () {
                          btnclick('乘');
                        },
                        child: Text('×',
                            style: TextStyle(
                                color: Color(int.parse(list[1]['color'])),
                                fontSize: 30)),
                        shape: CircleBorder(
                            side: BorderSide(
                                color: Color(int.parse(list[1]['bgc'])))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                ],
              ),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('4');
                        },
                        child: const Text('4',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('5');
                        },
                        child: const Text('5',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(30),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('6');
                        },
                        child: const Text('6',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(24),
                        color: Color(int.parse(list[2]['bgc'])),
                        splashColor: Color(int.parse(list[2]['bgc'])),
                        onPressed: () {
                          btnclick('减');
                        },
                        child: Text('—',
                            style: TextStyle(
                                color: Color(int.parse(list[2]['color'])),
                                fontSize: 30)),
                        shape: CircleBorder(
                            side: BorderSide(
                                color: Color(int.parse(list[2]['bgc'])))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                ],
              ),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('1');
                        },
                        child: const Text('1',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('2');
                        },
                        child: const Text('2',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(29),
                        color: const Color(0xFF3B3B3B),
                        splashColor: Colors.grey,
                        onPressed: () {
                          numClick('3');
                        },
                        child: const Text('3',
                            style:
                                TextStyle(color: Colors.white, fontSize: 30)),
                        shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFF3B3B3B))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                  Expanded(
                    child: Container(
                      child: MaterialButton(
                        padding: EdgeInsets.all(24),
                        color: Color(int.parse(list[3]['bgc'])),
                        splashColor: Color(int.parse(list[3]['bgc'])),
                        onPressed: () {
                          btnclick('加');
                        },
                        child: Text('+',
                            style: TextStyle(
                                color: Color(int.parse(list[3]['color'])),
                                fontSize: 30)),
                        shape: CircleBorder(
                            side: BorderSide(
                                color: Color(int.parse(list[3]['bgc'])))),
                      ),
                      alignment: Alignment.center,
                    ),
                    flex: 1,
                  ),
                ],
              ),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Container(
                    child: MaterialButton(
                      padding: const EdgeInsets.only(
                          left: 70.0, top: 20.0, bottom: 20.0, right: 76.0),
                      color: const Color(0xFF3B3B3B),
                      splashColor: Colors.grey,
                      onPressed: () {
                        numClick('0');
                      },
                      child: const Text('0',
                          style: TextStyle(color: Colors.white, fontSize: 30)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                    ),
                    margin: const EdgeInsets.only(left: 10.0),
                    alignment: Alignment.center,
                  ),
                  Container(
                    child: MaterialButton(
                      padding: EdgeInsets.all(29),
                      color: const Color(0xFF3B3B3B),
                      splashColor: Colors.grey,
                      onPressed: () {
                        numClick('.');
                      },
                      child: const Text('.',
                          style: TextStyle(color: Colors.white, fontSize: 30)),
                      shape: const CircleBorder(
                          side: BorderSide(color: Color(0xFF3B3B3B))),
                    ),
                    alignment: Alignment.center,
                  ),
                  Container(
                    child: MaterialButton(
                      padding: EdgeInsets.all(24),
                      color: Colors.orange,
                      splashColor: Colors.orange,
                      onPressed: () {
                        btnclick('等于');
                      },
                      child: const Text('=',
                          style: TextStyle(color: Colors.white, fontSize: 30)),
                      shape: const CircleBorder(
                          side: BorderSide(color: Colors.orange)),
                    ),
                    alignment: Alignment.center,
                  ),
                ],
              ),
            ),
          ],
        ),
        Expanded(child: Container()),
      ],
    );
  }

  bool _activating = false;

  void numClick(String digit) {
    setState(() {
      if (tag == 1 || sums == '错误') {
        sums = '0';
        tag = 0;
      }
      if (digit == '.') {
        if (!sums.contains('.') && !sums.contains('e')) sums += '.';
      } else if (sums == '0') {
        sums = digit;
      } else if (sums.length < 20) {
        sums += digit;
      }
    });
  }

  Future<void> _activate() async {
    if (_activating) return;
    _activating = true;
    try {
      await activateApp(context);
    } catch (_) {
      if (mounted) defaultToast(context, '进入失败，请重试');
    } finally {
      _activating = false;
    }
  }

  String _format(num value) {
    if (!value.isFinite) return '错误';
    final text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  void _calculate() {
    if (flag.isEmpty) return;
    final left = num.tryParse(total), right = num.tryParse(sums);
    if (left == null || right == null) {
      sums = '错误';
    } else {
      switch (flag) {
        case '加':
          sums = _format(left + right);
          break;
        case '减':
          sums = _format(left - right);
          break;
        case '乘':
          sums = _format(left * right);
          break;
        case '除':
          sums = right == 0 ? '错误' : _format(left / right);
          break;
      }
    }
    flag = '';
  }

  void btnclick(String action) {
    if (sums == '55566686648') {
      _activate();
      return;
    }
    setState(() {
      for (final element in list) {
        element['color'] = '0xFFFFFFFF';
        element['bgc'] = '0xFFFF9800';
      }
      if (action == '重置') {
        sums = total = '0';
        flag = '';
        tag = 0;
        return;
      }
      if (action == '加/减' || action == '百分号') {
        final value = num.tryParse(sums);
        if (value == null) return;
        sums = _format(action == '加/减' ? -value : value / 100);
        tag = 0;
        return;
      }
      if (action == '等于') {
        _calculate();
        tag = 1;
        return;
      }
      final index = ['除', '乘', '减', '加'].indexOf(action);
      if (index < 0 || sums == '错误') return;
      if (flag.isNotEmpty && tag == 0) _calculate();
      if (sums == '错误') return;
      total = sums;
      flag = action;
      tag = 1;
      list[index]['bgc'] = '0xFFFFFFFF';
      list[index]['color'] = '0xFFFF9800';
    });
  }
}
