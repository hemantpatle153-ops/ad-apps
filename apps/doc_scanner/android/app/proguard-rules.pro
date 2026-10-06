# Picked up automatically by the Flutter Gradle plugin for release builds.

# The ads SDK pulls in WorkManager, whose Room database is created by
# reflection on the generated *_Impl class. R8 removed that constructor and
# every release build crashed on launch with "Failed to create an instance
# of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# ML Kit text recognition only bundles the Latin model; the plugin still
# references the optional Chinese/Devanagari/Japanese/Korean ones.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
