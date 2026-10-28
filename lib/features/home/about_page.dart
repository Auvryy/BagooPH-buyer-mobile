import 'package:flutter/material.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../auth/policy_page.dart';
import '../products/product_widgets.dart';

class AboutBagooPage extends StatefulWidget {
  const AboutBagooPage({super.key, required this.repository});
  final BuyerRepository repository;
  @override
  State<AboutBagooPage> createState() => _AboutBagooPageState();
}

class _AboutBagooPageState extends State<AboutBagooPage> {
  late Future<WebPage> _requirements;
  @override
  void initState() {
    super.initState();
    _requirements = widget.repository.registration();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About BagooPH')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const ProductPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProductHeading('Local finds, everyday value'),
                    Text(
                      'Discover products from Bagoo shops, compare options, and keep your favorites in one place.',
                      style: TextStyle(height: 1.7),
                    ),
                    SizedBox(height: 20),
                    ProductHeading('Shop and follow your delivery'),
                    Text(
                      'Use your Shopping Bag, review server-confirmed prices and vouchers, and choose the available delivery and payment options at checkout. Track deliveries, contact your shop or courier, and manage permitted returns from your account.',
                      style: TextStyle(height: 1.7),
                    ),
                    SizedBox(height: 20),
                    ProductHeading('Your buyer account'),
                    Text(
                      'Buyer registration is for adults aged 18 or older. Shopping and checkout eligibility follow the account and identity review recorded by Bagoo. Help & Support is available from Home and Profile.',
                      style: TextStyle(height: 1.7),
                    ),
                  ],
                ),
              ),
              FutureBuilder<WebPage>(
                future: _requirements,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        const Notice(
                          'Account policies could not load.',
                          error: true,
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _requirements = widget.repository
                                .registration(),
                          ),
                          child: const Text('Retry policies'),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final policies = mapOf(snapshot.data!.props['policies']);
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in const {
                        'terms_url': 'Terms of Service',
                        'privacy_url': 'Privacy Policy',
                      }.entries)
                        if (policies[entry.key] is String)
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PolicyPage(
                                  repository: widget.repository,
                                  path: policies[entry.key],
                                ),
                              ),
                            ),
                            child: Text(entry.value),
                          ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
