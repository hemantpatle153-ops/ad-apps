# Picked up automatically by the Flutter Gradle plugin for release builds.

# The ads SDK pulls in WorkManager, whose Room database is created by
# reflection on the generated *_Impl class. R8 removed that constructor and
# every release build crashed on launch with "Failed to create an instance
# of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# libmpv (media_kit) calls back into these classes from native code.
-keep class com.alexmercerind.** { *; }
