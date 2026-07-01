import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/doctors_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/doctors', builder: (context, state) => const DoctorsScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
  ],
);
