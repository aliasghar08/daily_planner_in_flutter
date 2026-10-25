importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyCIQJb6DHJ6WTw8Vwd04Vjf5Z380uIHWkw",
  authDomain: "daily-planner-593d8.firebaseapp.com",
  projectId: "daily-planner-593d8",
  storageBucket: "daily-planner-593d8.firebasestorage.app",
  messagingSenderId: "777337977048",
  appId: "1:777337977048:web:7b2f4c78224e77409a3fad"
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage(function(payload) {
  console.log('Received background message ', payload);
});