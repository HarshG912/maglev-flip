import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: 'https://hteolkfbjmouicmyuxqv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZW9sa2Ziam1vdWljbXl1eHF2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExOTQ4OTgsImV4cCI6MjA5Njc3MDg5OH0.-EfrXpGR4v7svfu8-a8e97-U3roS7P42uqJ5P1NFtYI',
  );

  final supabase = Supabase.instance.client;
  
  try {
    final data = await supabase.from('master_subjects').select().limit(1);
    if (data.isNotEmpty) {
      print('Columns in master_subjects:');
      for (var key in data.first.keys) {
        print('- $key');
      }
    } else {
      print('master_subjects is empty.');
    }
  } catch (e) {
    print('Error: $e');
  }
}
