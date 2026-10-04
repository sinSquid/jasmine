import 'package:flutter/material.dart';

import '../../configs/using_right_click_pop.dart';

Widget rightClickPop({
  required Widget child,
  required BuildContext context,
  bool canPop = true,
}) =>
    currentUsingRightClickPop()
        ? GestureDetector(
            onSecondaryTap: () {
              if (canPop && context.mounted) {
                Navigator.of(context).maybePop();
              }
            },
            child: child,
          )
        : child;
