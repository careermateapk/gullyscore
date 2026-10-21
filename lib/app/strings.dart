// All text in the app, in English and Hindi.
// A test checks that every key used in the code exists in both languages.

class Strings {
  static String get(String key, String lang) {
    final map = lang == 'hi' ? hi : en;
    return map[key] ?? en[key] ?? key;
  }

  static const Map<String, String> en = {
    'app_name': 'GullyScore',
  };

  static const Map<String, String> hi = {
    'app_name': 'GullyScore',
  };
}
