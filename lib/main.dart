import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // [MỚI]

import 'config/app_constants.dart';
import 'config/app_theme.dart';
import 'presentation/screens/auth/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load biến môi trường từ file .env
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("⚠️ Không tìm thấy file .env! Hãy tạo file .env ở thư mục gốc.");
  }

  // 2. Khởi tạo Supabase với Key lấy từ .env (thông qua AppConstants)
  await Supabase.initialize(
    url: AppConstants.supabaseUrl, 
    anonKey: AppConstants.supabaseAnonKey, 
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Lock App',
      theme: AppTheme.lightTheme, 
      home: const SplashScreen(),
    );
  }
}