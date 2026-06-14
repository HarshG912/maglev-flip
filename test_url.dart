import 'package:http/http.dart' as http;
void main() async {
  var url = 'https://hteolkfbjmouicmyuxqv.supabase.co/storage/v1/object/public/train_skins/Cyber%20Streak%20(The%20Neon%20Classic).png';
  try {
    var response = await http.get(Uri.parse(url));
    print('Status: ${response.statusCode}');
    print('Length: ${response.bodyBytes.length}');
  } catch (e) {
    print('Error: $e');
  }
}
