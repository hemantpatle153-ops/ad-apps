import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/report.dart';

/// Firebase settings (the `dice-dhamaal` project, shared with Dice Dhamaal,
/// Video Player and Expense Tracker). These client settings ship inside
/// every APK anyway; the database rules protect the data. A build can point
/// elsewhere with --dart-define=FIREBASE_API_KEY=... and the names below.
abstract final class FirebaseSetup {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY',
      defaultValue: 'AIzaSyCRyrPruZ67YefPw1brA4cv0G6AeT9A7gk');
  // TODO(release): register in.onlysoftware.roz_quiz in the Firebase
  // project and put its own App ID here. Until then this is Expense
  // Tracker's, which works for anonymous sign-in and database writes.
  static const appId = String.fromEnvironment('FIREBASE_APP_ID',
      defaultValue: '1:448997235311:android:45bce4ebd3466a856e8b9a');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID',
      defaultValue: 'dice-dhamaal');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID',
      defaultValue: '448997235311');
  static const dbUrl = String.fromEnvironment('FIREBASE_DB_URL',
      defaultValue: 'https://dice-dhamaal-default-rtdb.firebaseio.com');

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        databaseURL: dbUrl,
      );
}

/// Writes reports to `feedReports/<push id>` after anonymous sign-in.
/// Firebase starts only when the first report is sent, so the app opens
/// without touching the network for it.
class FirebaseReportSink implements ReportSink {
  FirebaseApp? _app;
  static const _timeout = Duration(seconds: 20);

  Future<FirebaseApp> _start() async => _app ??= Firebase.apps.isEmpty
      ? await Firebase.initializeApp(options: FirebaseSetup.options)
      : Firebase.app();

  @override
  Future<String> signIn() async {
    final auth = FirebaseAuth.instanceFor(app: await _start());
    final user = auth.currentUser;
    if (user != null) return user.uid;
    final cred = await auth.signInAnonymously().timeout(_timeout);
    return cred.user!.uid;
  }

  @override
  Future<void> send(ReportPayload payload) async {
    final db = FirebaseDatabase.instanceFor(
        app: await _start(), databaseURL: FirebaseSetup.dbUrl);
    await db
        .ref('feedReports')
        .push()
        .set({...payload.toJson(), 'at': ServerValue.timestamp})
        .timeout(_timeout);
  }
}
