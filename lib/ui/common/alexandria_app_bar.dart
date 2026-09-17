import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'identity_avatar_action.dart';

/// Builds the shared Alexandria app bar.
///
/// Produces a consistent [AppBar] across primary surfaces: a Newsreader
/// editorial title treatment per [AppTheme] and the [IdentityAvatarAction]
/// appended as the trailing action unless [showIdentityAction] is false.
///
/// Pass either a plain [title] string (optionally preceded by [titleIcon])
/// or a fully composed [titleWidget].
PreferredSizeWidget alexandriaAppBar({
  String? title,
  IconData? titleIcon,
  Widget? titleWidget,
  List<Widget>? actions,
  bool showIdentityAction = true,
}) {
  final titleText = Text(
    title ?? '',
    style: const TextStyle(
      fontFamily: 'Newsreader',
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: AppTheme.textColor,
    ),
  );

  return AppBar(
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    title: titleWidget ??
        (titleIcon == null
            ? titleText
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(titleIcon, color: AppTheme.primaryAccent),
                  const SizedBox(width: 10),
                  Flexible(child: titleText),
                ],
              )),
    actions: [
      ...?actions,
      if (showIdentityAction) const IdentityAvatarAction(),
    ],
  );
}
