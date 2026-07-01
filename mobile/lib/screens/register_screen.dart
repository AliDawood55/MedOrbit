import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../services/api_client.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'patient';
  String? _error;
  String? _success;
  bool _loading = false;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final locale = Localizations.localeOf(context).languageCode;
      await ref.read(authApiProvider).register({
        'fullName': _fullName.text,
        'email': _email.text,
        'phone': _phone.text,
        'password': _password.text,
        'role': _role,
        'preferredLanguage': locale,
      });
      setState(() => _success = l10n.registerSuccess);
    } catch (_) {
      setState(() => _error = l10n.errorGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navRegister)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _fullName,
                decoration: InputDecoration(labelText: l10n.fullName),
                validator: (v) => (v == null || v.isEmpty) ? l10n.fullName : null,
              ),
              TextFormField(
                controller: _email,
                decoration: InputDecoration(labelText: l10n.email),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || v.isEmpty) ? l10n.email : null,
              ),
              TextFormField(
                controller: _phone,
                decoration: InputDecoration(labelText: l10n.phone),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(labelText: l10n.password),
                obscureText: true,
                validator: (v) => (v == null || v.length < 8) ? l10n.password : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: InputDecoration(labelText: l10n.roleLabel),
                items: [
                  DropdownMenuItem(value: 'patient', child: Text(l10n.rolePatient)),
                  DropdownMenuItem(value: 'doctor', child: Text(l10n.roleDoctor)),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'patient'),
              ),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_success != null) Text(_success!, style: const TextStyle(color: Colors.green)),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(l10n.registerSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
