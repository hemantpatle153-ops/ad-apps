import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../logic/report.dart';

/// Firebase settings (the `dice-dhamaal` project shared with the other
/// apps; copied from Expense Tracker). These client settings ship inside
/// every APK anyway; the database rules protect the data. A build can point
/// elsewhere with --dart-define=FIREBASE_API_KEY=... and the other names.
abstract final class FirebaseSetup {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY',
      defaultValue: 'AIzaSyCRyrPruZ67YefPw1brA4cv0G6AeT9A7gk');
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
/// Firebase starts only when the first report is sent, so the app never
/// talks to Firebase unless the user reports something.
class FirebaseReportBackend implements ReportBackend {
  FirebaseApp? _app;
  static const _timeout = Duration(seconds: 20);

  Future<FirebaseApp> _start() async => _app ??= Firebase.apps.isEmpty
      ? await Firebase.initializeApp(options: FirebaseSetup.options)
      : Firebase.app();

  @override
  Future<void> send(ReportDraft draft) async {
    final app = await _start().timeout(_timeout);
    final auth = FirebaseAuth.instanceFor(app: app);
    final uid = auth.currentUser?.uid ??
        (await auth.signInAnonymously().timeout(_timeout)).user!.uid;
    final db = FirebaseDatabase.instanceFor(app: app, databaseURL: FirebaseSetup.dbUrl);
    await db
        .ref('feedReports')
        .push()
        .set(draft.toEntry(uid: uid, at: ServerValue.timestamp))
        .timeout(_timeout);
  }
}
