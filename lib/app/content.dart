// Privacy policy, terms, about us, blog posts and social links. They live in
// assets/content/pages.json, which the online service also uses for its web
// pages, so the app and the website always say the same thing.
import 'dart:convert';

import 'package:flutter/services.dart';

class InfoPage {
  InfoPage({required this.title, required this.short, required this.sections});
  final String title;
  final List<String> short;
  final List<(String, List<String>)> sections;
}

class BlogPost {
  BlogPost({required this.slug, required this.date, required this.title, required this.summary});
  final String slug;
  final String date;
  final String title;
  final String summary;
}

class AppContent {
  AppContent._(this._j);
  final Map<String, dynamic> _j;

  static AppContent? _cache;

  static Future<AppContent> load() async {
    return _cache ??= AppContent._(jsonDecode(await rootBundle.loadString('assets/content/pages.json')) as Map<String, dynamic>);
  }

  String get updated => (_j['updated'] as String?) ?? '';
  String get contact => (_j['contact'] as String?) ?? '';

  InfoPage page(String kind, String lang) {
    final both = _j['pages'][kind] as Map<String, dynamic>;
    final j = (both[lang] ?? both['en']) as Map<String, dynamic>;
    return InfoPage(
      title: j['title'] as String,
      short: [for (final s in j['short'] as List) s as String],
      sections: [
        for (final s in j['sections'] as List) (s[0] as String, [for (final x in s[1] as List) x as String]),
      ],
    );
  }

  /// Link for a social network ('instagram', 'facebook', 'youtube', 'x'); empty when not set yet.
  String social(String key) => ((_j['social'] as Map?)?[key] as String?) ?? '';

  List<BlogPost> get blog => [
        for (final b in (_j['blog'] as List? ?? const []))
          BlogPost(slug: b['slug'] as String, date: b['date'] as String, title: b['title'] as String, summary: b['summary'] as String),
      ];
}
