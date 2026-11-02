import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';

bool _validPolicySections(Object? rawSections) {
  if (rawSections is! List || rawSections.isEmpty) return false;
  final titles = <String>{};
  for (final rawSection in rawSections) {
    if (rawSection is! Map || rawSection.keys.any((key) => key is! String)) {
      return false;
    }
    final section = Map<String, dynamic>.from(rawSection);
    final title = section['title'];
    final paragraphs = section['paragraphs'];
    if (title is! String ||
        title.trim().isEmpty ||
        !titles.add(title) ||
        paragraphs is! List ||
        paragraphs.isEmpty ||
        paragraphs.any(
          (paragraph) => paragraph is! String || paragraph.trim().isEmpty,
        )) {
      return false;
    }
  }
  return true;
}

bool _validPolicyDocument(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) return false;
  final document = Map<String, dynamic>.from(value);
  for (final key in ['title', 'version', 'introduction']) {
    final content = document[key];
    if (content is! String || content.trim().isEmpty) return false;
  }
  return _validPolicySections(document['sections']);
}

class PolicyPage extends StatefulWidget {
  const PolicyPage({super.key, required this.repository, required this.path});
  final BuyerRepository repository;
  final String path;
  @override
  State<PolicyPage> createState() => _PolicyPageState();
}

class _PolicyPageState extends State<PolicyPage> {
  late Future<WebPage> _page;
  @override
  void initState() {
    super.initState();
    _page = widget.repository.document(widget.path);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account policies')),
    body: SafeArea(
      child: FutureBuilder<WebPage>(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Notice(snapshot.error.toString(), error: true),
                    TextButton(
                      onPressed: () => setState(
                        () => _page = widget.repository.document(widget.path),
                      ),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rawDocument = snapshot.data!.props['document'];
          if (!_validPolicyDocument(rawDocument)) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Notice(
                      'Policy text could not be fully confirmed. Try loading it again.',
                      error: true,
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _page = widget.repository.document(widget.path),
                      ),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          final document = Map<String, dynamic>.from(rawDocument as Map);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    document['title']?.toString() ?? 'Account policy',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Version ${document['version'] ?? ''}'),
                  const SizedBox(height: 24),
                  Text(
                    document['introduction']?.toString() ?? '',
                    style: const TextStyle(height: 1.7),
                  ),
                  for (final section in mapsOf(document['sections'])) ...[
                    const SizedBox(height: 24),
                    Text(
                      section['title']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final paragraph in stringsOf(section['paragraphs']))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          paragraph.toString(),
                          style: const TextStyle(height: 1.7),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
