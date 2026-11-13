import 'package:flutter/material.dart';

/// Global navigator key, used by services (e.g. notification taps) to
/// navigate without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();