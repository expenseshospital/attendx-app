import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://txamymcimbdqyadcvowt.supabase.co',
    anonKey: 'sb_publishable_BHdMd0PLQKilk8hGbmC39Q_JENVO2S-',
  );
  
  runApp(const AttendXApp());
}

class AttendXApp extends StatelessWidget {
  const AttendXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D6FE8),
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
