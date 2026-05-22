import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/listing_model.dart';
import 'providers/auth_provider.dart';
import 'providers/listings_provider.dart';
import 'providers/post_form_provider.dart';
import 'services/notification_service.dart';
import 'utils/app_routes.dart';
import 'utils/app_theme.dart';

import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/set_password_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/detail/listing_detail_screen.dart';
import 'screens/post/post_form_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService().init();

  await Hive.initFlutter();
  Hive.registerAdapter(ListingModelAdapter());
  await Hive.openBox<ListingModel>('recentListings');

  runApp(const CampusLostFoundApp());
}

class CampusLostFoundApp extends StatefulWidget {
  const CampusLostFoundApp({super.key});

  @override
  State<CampusLostFoundApp> createState() => _CampusLostFoundAppState();
}

class _CampusLostFoundAppState extends State<CampusLostFoundApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ListingsProvider()),
        ChangeNotifierProvider(create: (_) => PostFormProvider()),
      ],
      child: MaterialApp(
        title: 'Campus Lost & Found',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: (settings) => _generateRoute(settings),
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return _fade(SplashScreen(toggleTheme: _toggleTheme));
      case AppRoutes.login:
        return _slide(const LoginScreen());
      case AppRoutes.setPassword:
        return _fade(const SetPasswordScreen());
      case AppRoutes.feed:
        return _fade(HomeScreen(toggleTheme: _toggleTheme, themeMode: _themeMode));
      case AppRoutes.listingDetail:
        final listing = settings.arguments as dynamic;
        return _slide(ListingDetailScreen(listing: listing));
      case AppRoutes.postForm:
        final listing = settings.arguments as dynamic;
        return _slideUp(PostFormScreen(existingListing: listing));
      case AppRoutes.editProfile:
        return _slide(const EditProfileScreen());
      default:
        return _fade(SplashScreen(toggleTheme: _toggleTheme));
    }
  }

  PageRoute _fade(Widget page) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      );

  PageRoute _slide(Widget page) => PageRouteBuilder(
        settings: RouteSettings(name: page.runtimeType.toString()),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) {
          final tween = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(position: anim.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 320),
      );

  PageRoute _slideUp(Widget page) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) {
          final tween = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(position: anim.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 380),
      );
}