import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../core/contact_input.dart';
import '../../core/uploads.dart';
import '../../core/web_session.dart';
import '../../core/widgets.dart';
import '../home/product_card.dart';
import 'profile_repository.dart';
export '../../core/file_selection.dart' show pickUpload;

class ProfilePanel extends StatelessWidget {
  const ProfilePanel({super.key, required this.child, this.padding = 20});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(BagooTheme.panelRadius),
      border: Border.all(color: BagooTheme.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x040F172A),
          offset: Offset(0, 2),
          blurRadius: 8,
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class ProfileHeading extends StatelessWidget {
  const ProfileHeading(this.title, this.description, this.icon, {super.key});
  final String title, description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BagooTheme.rose,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExcludeSemantics(
                child: Icon(icon, color: BagooTheme.strong, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                height: 1.7,
                color: BagooTheme.muted,
              ),
            ),
          ),
        const Divider(height: 32),
      ],
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.user, this.session, {super.key, this.size = 56});
  final Map<String, dynamic> user;
  final WebSession session;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox.square(
      dimension: size,
      child: imageUri(session, user['avatar']) == null
          ? ColoredBox(
              color: BagooTheme.rose,
              child: Center(
                child: Text(
                  (user['name']?.toString().trim().characters.firstOrNull ??
                          'B')
                      .toUpperCase(),
                  style: TextStyle(
                    color: BagooTheme.strong,
                    fontSize: size * .4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          : RemoteImage(uri: imageUri(session, user['avatar'])),
    ),
  );
}

String identityLabel(Map<String, dynamic> user) => switch (user['kyc_status']) {
  'approved' || 'verified' => 'Verified Buyer',
  'pending_approval' => 'KYC In Review',
  'rejected' => 'KYC Action Required',
  _ => 'Unverified Account',
};
bool reviewed(Map<String, dynamic> user) =>
    ['approved', 'verified'].contains(user['kyc_status']);

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String description,
  String button,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(description, style: const TextStyle(height: 1.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(button),
          ),
        ],
      ),
    ) ??
    false;

abstract class ProfileFormState<T extends StatefulWidget> extends State<T> {
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  String? problem, success;
  Map<String, String> errors = {};
  void onFailure(BackendException error) {}

  Future<bool> perform(
    Future<String?> Function() action, {
    bool validate = true,
  }) async {
    if (busy || (validate && formKey.currentState?.validate() == false)) {
      return false;
    }
    setState(() {
      busy = true;
      problem = null;
      success = null;
      errors = {};
    });
    try {
      final result = await action();
      if (mounted) setState(() => success = result);
      return true;
    } on BackendException catch (e) {
      if (mounted) {
        setState(() {
          problem = e.message;
          errors = e.fields;
          onFailure(e);
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(
          () => problem = 'This action could not finish. Check the current details before trying again.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String key,
    String label,
    TextEditingController controller, {
    bool required = true,
    bool secret = false,
    bool enabled = true,
    int min = 1,
    int? max,
    int lines = 1,
    TextInputType? keyboard,
    Iterable<String>? autofill,
    String? hint,
    String? Function(String)? check,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: controller,
      enabled: enabled && !busy,
      obscureText: secret,
      minLines: lines,
      maxLines: secret ? 1 : lines,
      keyboardType: keyboard,
      inputFormatters: keyboard == TextInputType.phone
          ? [mobileNumberFormatter]
          : null,
      autofillHints: autofill,
      maxLength: max,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 5,
        errorText: errors[key],
        errorMaxLines: 5,
        counterText: '',
      ),
      validator: (v) {
        final value = secret ? v ?? '' : v?.trim() ?? '';
        if (required && value.isEmpty) return 'Enter ${label.toLowerCase()}.';
        if (value.isNotEmpty && value.length < min) {
          return 'Use at least $min characters.';
        }
        if (max != null && value.length > max) {
          return 'Use at most $max characters.';
        }
        return check?.call(value) ??
            (keyboard == TextInputType.phone ? mobileNumberValidator(v) : null);
      },
    ),
  );

  Widget content(List<Widget> children) => Form(
    key: formKey,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProfilePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Notice(
                    [
                      problem!,
                      ...errors.entries.map(
                        (e) => '${e.key.replaceAll('_', ' ')}: ${e.value}',
                      ),
                    ].join('\n'),
                    error: true,
                  ),
                ),
              if (success != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Notice(success!),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ProfilePagination extends StatelessWidget {
  const ProfilePagination(
    this.page,
    this.onPage, {
    super.key,
    this.disabled = false,
  });
  final Map<String, dynamic> page;
  final ValueChanged<int> onPage;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
    final current = (page['current_page'] as num?)?.toInt() ?? 1;
    final last = (page['last_page'] as num?)?.toInt() ?? 1;
    if (last <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: disabled || current <= 1
                ? null
                : () => onPage(current - 1),
            child: const Text('Previous'),
          ),
          Text('$current of $last'),
          OutlinedButton(
            onPressed: disabled || current >= last
                ? null
                : () => onPage(current + 1),
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class PrivateDocumentPage extends StatefulWidget {
  const PrivateDocumentPage({
    super.key,
    required this.repository,
    required this.path,
    required this.title,
  });
  final ProfileRepository repository;
  final String path, title;
  @override
  State<PrivateDocumentPage> createState() => _PrivateDocumentPageState();
}

class _PrivateDocumentPageState extends State<PrivateDocumentPage> {
  late Future<RemoteDocument> _document;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _document = widget.repository.session.documentBytes(widget.path);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: FutureBuilder(
        future: _document,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Notice(
                      snapshot.error is BackendException
                          ? (snapshot.error as BackendException).message
                          : 'The document could not load.',
                      error: true,
                    ),
                    TextButton(
                      onPressed: () => setState(_load),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          final document = snapshot.data;
          if (document == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return document.mime == 'application/pdf'
              ? PdfViewer.data(
                  document.bytes,
                  sourceName: widget.title,
                  params: PdfViewerParams(
                    linkHandlerParams: PdfLinkHandlerParams(onLinkTap: (_) {}),
                  ),
                )
              : Center(
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Image.memory(
                      document.bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Notice(
                        'This image cannot be displayed.',
                        error: true,
                      ),
                    ),
                  ),
                );
        },
      ),
    ),
  );
}
