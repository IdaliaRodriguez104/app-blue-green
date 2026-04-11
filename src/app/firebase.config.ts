// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
import { getDatabase } from "firebase/database";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyDKGr7Dhc845yssedaRbniHvJIjt4Vh3mI",
  authDomain: "app-blue-green.firebaseapp.com",
  projectId: "app-blue-green",
  storageBucket: "app-blue-green.firebasestorage.app",
  messagingSenderId: "595027122369",
  appId: "1:595027122369:web:eb4b10ecf0c9ed86299c40",
  measurementId: "G-QYGVB6812W"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
export const db = getDatabase(app);