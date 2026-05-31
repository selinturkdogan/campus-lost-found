# Campus L&F (Lost & Found Board)

A Flutter mobile application that lets university students report and recover
lost items on campus. 

## Table of Contents

- [About](#about)
- [Features](#features)
- [Tech stack](#tech-stack)
- [Architecture at a glance](#architecture-at-a-glance)
- [Project structure](#project-structure)
- [How to run](#how-to-run)
- [Deploying the backend](#deploying-the-backend)
- [Documentation](#documentation)

---

## About

Campus L&F is a single-developer Flutter app. The Flutter client talks to
Firebase for data, files, authentication, and push delivery; a small set of
Cloud Functions handles the trusted server-side work (sending the temporary
password by email, fanning out notifications, keeping comment counters
accurate). There is no separate backend server.

The application is designed for a university community: only users with an
administrator-approved email domain can register, and the entire workflow
(posting, browsing, chatting, commenting) is tailored to a closed campus
audience.

---

## Features

### Authentication
- **Continue with Google** entry point that verifies the email belongs to an
  allowed domain.
- A Cloud Function generates a 12-character temporary password and emails it
  to the user through Gmail SMTP.
- Forced password change on first sign-in (the user cannot navigate away
  until a new password is set).
- Branded "Forgot password" reset email, also sent from a Gmail account.
- Change password from the profile screen, with re-authentication.

### Feed and listings
- Two-tab feed (Lost / Found) with explanatory subtitles.
- Pagination — ten listings at a time with an explicit **Load more** action.
- Pull-to-refresh on every tab.
- Keyword search and filtering by campus location and category.
- Instagram-style listing cards: header (avatar + name + meta), 16:9 photo
  with Lost/Found badge, action row with comment count and share button.
- Post creation form with category and campus location, optional photo, and
  a per-listing **chat enable/disable** toggle with a required pickup note
  when chat is off.
- Edit, delete (with confirmation), mark as resolved, and extend expiry for
  your own listings.

### Detail screen
- Full description, photo, category badge, and metadata.
- **Google Maps preview** — tap the map to open the device's native Google
  Maps application.
- Poster card with avatar, email, optional phone/city/department/bio
  (controlled by privacy toggles on the user side).
- **Comments** section with public discussion, `@`-mentions, and inline
  highlighting of mentioned users.
- **Share** button that produces a text payload for WhatsApp / SMS / email.

### Chat (encrypted)
- One-to-one chat scoped to each listing.
- Messages are encrypted on the device with **AES-256-CBC** before being
  written to Firestore (per-message random IV).
- Text messages, image messages, and location messages are all supported.
- Per-chat unread counters maintained by a Cloud Function.
- **Soft delete** — hiding a conversation only affects your own view; a new
  message brings it back for both participants.
- Push notifications use a generic body (no message content leaks server-side
  because the server cannot decrypt it).

### Profile
- Avatar upload (compressed to ≤300 KB).
- Display name, phone, city, department, biography.
- Per-field privacy toggles for phone and city.
- Reusable `UserAvatar` widget used in feed cards, chat header, messages
  list, and comments.

### Notifications
- In-app notifications bell with unread badge.
- Four notification types: chat, comment, mention, expiry.
- Push notifications via Firebase Cloud Messaging.
- FCM token is cleared on logout to prevent leaks across accounts on a
  shared device.

### Admin
- Admin Panel for resolving or deleting any listing (active or resolved).
- Allowed Domains screen for adding and removing email domains that may
  register. An empty list blocks new sign-ups.
- Domain edits and config writes are protected by Firestore rules
  (administrators only).

### Other polish
- Image compression pipeline (1280 px / JPEG q85) shared by listing photos,
  chat photos, and avatars — typically reduces a 3-5 MB photo to
  ~200-400 KB without visible loss.
- Offline cache of recent listings via Hive, with an offline banner.
- Light and dark themes.
- Custom **Constellation Search** logo (splash, login header, app icon).

---

## Tech stack

| Layer | Technology |
|---|---|
| UI | Flutter 3.x, Material 3 |
| State | Provider (ChangeNotifier) |
| Database | Cloud Firestore |
| Authentication | Firebase Authentication + `google_sign_in` |
| File storage | Firebase Storage |
| Push delivery | Firebase Cloud Messaging |
| Backend logic | Cloud Functions (Node.js 24, 2nd gen) |
| Transactional email | Nodemailer + Gmail SMTP (App Password) |
| Encryption | `encrypt` (AES-256-CBC, PKCS7 padding) |
| Maps | `google_maps_flutter` (lite) + `url_launcher` |
| Local cache | Hive |
| Image compression | `flutter_image_compress` + `path_provider` |
| Sharing | `share_plus` |
| Icons | `flutter_launcher_icons` |
| Fonts | DM Sans via `google_fonts` |

---

## Architecture at a glance

```
   ┌────────────────────────────┐
   │       Flutter Client       │
   │  Screens / Providers /     │
   │  Services / Widgets        │
   └────────────┬───────────────┘
                │  Firebase SDKs
                ▼
   ┌────────────────────────────┐
   │          Firebase          │
   │  Auth   Firestore  Storage │
   │              │             │
   │              ▼             │
   │     Cloud Functions        │
   │     (Node.js 24)           │
   │      │            │        │
   │      ▼            ▼        │
   │    FCM        Gmail SMTP   │
   └────────────────────────────┘
```

Full architecture, storage management, and implementation details are
documented in `TechnicalDoc_CampusLF.docx` (see [Documentation](#documentation)).

---

## Project structure

```
campus_lf_new/
├── lib/
│   ├── main.dart                 Bootstrap + route table
│   ├── firebase_options.dart     Generated by FlutterFire CLI
│   ├── models/
│   │   └── listing_model.dart    Hive-typed listing object
│   ├── providers/
│   │   ├── auth_provider.dart
│   │   ├── listings_provider.dart
│   │   └── post_form_provider.dart
│   ├── services/
│   │   ├── comment_service.dart     Comment CRUD + @-mention search
│   │   ├── domains_service.dart     Allowed-domains read/write
│   │   ├── message_crypto.dart      AES-256 chat encryption
│   │   └── notification_service.dart FCM token management
│   ├── screens/
│   │   ├── auth/    login_screen + set_password_screen
│   │   ├── home/    home_screen + feed_tab
│   │   ├── detail/  listing_detail_screen
│   │   ├── post/    post_form_screen
│   │   ├── my_posts/, messages/, chat/, notifications/
│   │   ├── profile/ profile_screen + edit_profile_screen
│   │   ├── admin/   admin_panel + domain_settings_screen
│   │   └── splash_screen.dart
│   ├── widgets/
│   │   ├── listing_card.dart        Instagram-style card
│   │   ├── comments_section.dart    Composer + mention picker
│   │   └── user_avatar.dart
│   └── utils/
│       ├── app_routes.dart
│       ├── app_theme.dart
│       └── image_utils.dart         Compression helper
│
├── functions/                   Cloud Functions source
│   ├── index.js
│   ├── package.json
│   └── .env.example             Sample environment variables
│
├── assets/
│   ├── images/                  Google "G" logo, etc.
│   └── logo/                    Constellation Search logo set
│       ├── png/
│       ├── svg/
│       ├── android/
│       └── ios/
│
├── firestore.rules              Security rules
├── firestore.indexes.json       Composite-index declarations
├── firebase.json                Firebase project config
├── pubspec.yaml
└── README.md
```

---

## How to run

### Prerequisites

- Flutter SDK 3.0+
- A Firebase project on the Blaze (pay-as-you-go) plan — required for Cloud
  Functions outbound network access (Gmail SMTP) and any usage above the
  free tier.
- A Google account with 2-Step Verification enabled (needed to issue an
  **App Password** for Gmail SMTP).
- Android Studio or Xcode for device deployment, or a physical Android
  device with USB debugging enabled.

### 1. Clone the repository

```bash
git clone https://github.com/<your-account>/campus_lf_new.git
cd campus_lf_new
```

### 2. Install Flutter dependencies

```bash
flutter pub get
```

### 3. Connect your own Firebase project

The repository does not ship with Firebase credentials. You will need to
generate your own:

```bash
# Install the FlutterFire CLI if you do not already have it
dart pub global activate flutterfire_cli

# Link a Firebase project (creates lib/firebase_options.dart and
# android/app/google-services.json automatically)
flutterfire configure
```

### 4. Configure the Cloud Functions environment

```bash
cd functions
cp .env.example .env
# Edit .env and fill in GMAIL_USER and GMAIL_APP_PASSWORD
npm install
cd ..
```

`GMAIL_USER` is a Gmail address; `GMAIL_APP_PASSWORD` is a 16-character app
password generated from
<https://myaccount.google.com/apppasswords>.

### 5. Generate application icons

```bash
flutter pub run flutter_launcher_icons
```

### 6. Run on a device

```bash
flutter run
```

The first build takes a few minutes. Subsequent runs use Flutter's hot reload
(`r`) and hot restart (`R`).

### 7. First-time admin setup

After deploying for the first time the database has no allowed domains, so
nobody can register. Bootstrap an administrator manually:

1. Create the first account through Firebase Authentication directly (Auth
   tab → Add user) using your own email.
2. In Firestore, add a document at `users/{your-uid}` with
   `isAdmin: true` and any other profile fields you want.
3. Sign in to the app with that account. From Profile → **Allowed Domains**
   you can now add the email domain you want to admit (for example
   `final.edu.tr`).

---

## Deploying the backend

```bash
# Deploy security rules and composite indexes
firebase deploy --only firestore

# Deploy Cloud Functions
firebase deploy --only functions
```

The first deployment of `firestore:indexes` can take a few minutes while
Firestore builds the new indexes. The Messages screen depends on a
collection-group index on `chats.participants`, which is declared in
`firestore.indexes.json`.

---

## Author

**Selin Türkdoğan** 
