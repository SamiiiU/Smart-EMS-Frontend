// Keep Firebase SDK version aligned with firebase_core_web's supported version.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
firebase.initializeApp({
  apiKey: 'AIzaSyBYFh5HgsMavnDySwAByQ6Pp9HcehXZ6Rc',
  authDomain: 'babul-ems.firebaseapp.com',
  projectId: 'babul-ems',
  storageBucket: 'babul-ems.firebasestorage.app',
  messagingSenderId: '599728013512',
  appId: '1:599728013512:web:ea69d124ff63c33bcda5fd'
});
// SDK displays notification payloads in background; no duplicate showNotification.
firebase.messaging();