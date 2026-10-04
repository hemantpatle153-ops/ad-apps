import 'package:flutter/material.dart';

/// Material 3 light and dark themes from one seed colour per app.
ThemeData buildTheme(Color seed, Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
    );
