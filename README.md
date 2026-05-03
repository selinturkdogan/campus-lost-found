# Campus Lost & Found

A university-specific mobile application where students can post lost or found items, browse active listings, and contact item owners — built with Flutter and Firebase.

---

## Features

- Browse lost and found listings in real-time with Lost, Found, and All tabs
- Post a listing with title, description, category, campus location, and optional photo
- Edit, delete, and mark your own listings as resolved
- Search listings by keyword or filter by campus location
- In-app messaging — send messages to item posters directly from the listing detail
- Messages inbox — view all incoming messages across your listings
- Push notifications when someone messages you or a new listing is posted
- Google Maps pin showing where the item was lost or found on campus
- Admin panel for moderating and removing inappropriate listings
- Offline browsing support via local cache
- Dark and light theme toggle

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| State Management | Provider |
| Backend | Firebase Firestore |
| Authentication | Firebase Auth |
| Storage | Firebase Storage |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Local Cache | Hive |
| Maps | Google Maps Flutter |
| Image Loading | Cached Network Image |
| Font | DM Sans (Google Fonts) |

---

## Project Structure

```
lib/
├── main.dart
├── models/
│   └── listing_model.dart
├── providers/
│   ├── auth_provider.dart
│   ├── listings_provider.dart
│   └── post_form_provider.dart
├── screens/
│   ├── admin/
│   │   └── admin_panel_screen.dart
│   ├── auth/
│   │   └── login_screen.dart
│   ├── detail/
│   │   └── listing_detail_screen.dart
│   ├── home/
│   │   ├── home_screen.dart
│   │   └── feed_tab.dart
│   ├── messages/
│   │   └── messages_screen.dart
│   ├── my_posts/
│   │   └── my_posts_screen.dart
│   ├── post/
│   │   └── post_form_screen.dart
│   ├── profile/
│   │   └── profile_screen.dart
│   └── splash_screen.dart
├── services/
│   └── notification_service.dart
├── utils/
│   ├── app_routes.dart
│   └── app_theme.dart
└── widgets/
    └── listing_card.dart
```

---

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/selinturkdogan/campus-lost-found.git
cd campus-lost-found
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Add Firebase credentials

This project requires your own Firebase project. Add the following files which are excluded from the repository:

- `android/app/google-services.json` — download from Firebase Console
- `lib/firebase_options.dart` — generate using FlutterFire CLI

### 4. Run the app

Connect a physical Android device via USB with USB debugging enabled, then:

```bash
flutter run
```
