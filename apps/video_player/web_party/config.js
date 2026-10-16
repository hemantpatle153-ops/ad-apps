// Same Firebase project and database as the Android app (dice-dhamaal).
// These client settings ship inside every APK anyway; the database rules
// protect the data.
export const firebaseConfig = {
  apiKey: 'AIzaSyCRyrPruZ67YefPw1brA4cv0G6AeT9A7gk',
  authDomain: 'dice-dhamaal.firebaseapp.com',
  databaseURL: 'https://dice-dhamaal-default-rtdb.firebaseio.com',
  projectId: 'dice-dhamaal',
  messagingSenderId: '448997235311',
  appId: '1:448997235311:android:1b54beb30bb19ea96e8b9a',
};

// Play Store page of the app, shown to web viewers.
export const playStoreUrl =
  'https://play.google.com/store/apps/details?id=in.onlysoftware.video_player';
