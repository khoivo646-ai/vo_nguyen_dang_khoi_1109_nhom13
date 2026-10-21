import 'package:flutter_dotenv/flutter_dotenv.dart';

// ignore: camel_case_types
class Config_URL {
  static String get baseUrl {
    final url = dotenv.env['BASE_URL'];
    if (url == null || url.isEmpty) {
      return "https://10.0.2.2:7092/api/";
    }
    return url;
  }
}
