import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_text_field.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../data/profile_models.dart';

const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Builds the PATCH body from what was typed. Empty fields mean "unchanged"; [cleared] keys are sent as null.
/// Pure, unit-tested. Returns the body, or an error message for the first invalid field.
({Map<String, dynamic> body, String? error}) buildProfilePatch({
  required bool admin,
  String designation = '',
  String experienceYears = '',
  String phone = '',
  String medicalNotes = '',
  String? bloodGroup,
  Shift? shift,
  String? status,
  List<Certification>? certifications,
  Set<String> cleared = const {},
}) {
  final body = <String, dynamic>{};
  final d = designation.trim();
  if (d.isNotEmpty) body['designation'] = d;
  if (admin) {
    final e = experienceYears.trim();
    if (e.isNotEmpty) {
      final n = int.tryParse(e);
      if (n == null || n < 0 || n > 60) return (body: const {}, error: 'Experience must be a whole number of years (0–60)');
      body['experienceYears'] = n;
    }
    final p = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (p.isNotEmpty) {
      if (!RegExp(r'^\+\d{8,15}$').hasMatch(p)) return (body: const {}, error: 'Phone must be in international form, e.g. +9198…');
      body['phoneE164'] = p;
    }
    final m = medicalNotes.trim();
    if (m.isNotEmpty) body['medicalNotes'] = m;
    if (bloodGroup != null) body['bloodGroup'] = bloodGroup;
    if (shift != null) body['shift'] = shift.wire;
    if (status != null) body['status'] = status;
    if (certifications != null) body['certifications'] = certifications.map((c) => c.toJson()).toList();
  }
  for (final k in cleared) {
    if (!admin && k != 'designation') continue;
    body[k] = null;
  }
  return (body: body, error: null);
}

/// Admin: every editable field. Self: designation only (the server enforces the same).
Future<Map<String, dynamic>?> showProfileEditor(BuildContext context, {required ProfileDetail profile, required bool admin}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EditorSheet(profile: profile, admin: admin),
  );
}

class _EditorSheet extends StatefulWidget {
  const _EditorSheet({required this.profile, required this.admin});
  final ProfileDetail profile;
  final bool admin;
  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final TextEditingController _designation;
  late final TextEditingController _experience;
  late final TextEditingController _phone;
  late final TextEditingController _medical;
  late final TextEditingController _certName;
  String? _blood;
  Shift? _shift;
  String? _status;
  DateTime? _certExpiry;
  List<Certification>? _certs;
  final _cleared = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _designation = TextEditingController();
    _experience = TextEditingController();
    _phone = TextEditingController();
    _medical = TextEditingController();
    _certName = TextEditingController();
  }

  @override
  void dispose() {
    _designation.dispose();
    _experience.dispose();
    _phone.dispose();
    _medical.dispose();
    _certName.dispose();
    super.dispose();
  }

  String _current(String? v) => v == null || v.isEmpty ? 'Not set' : 'Current: $v';

  void _save() {
    final r = buildProfilePatch(
      admin: widget.admin,
      designation: _designation.text,
      experienceYears: _experience.text,
      phone: _phone.text,
      medicalNotes: _medical.text,
      bloodGroup: _blood,
      shift: _shift,
      status: _status,
      certifications: _certs,
      cleared: _cleared,
    );
    if (r.error != null) return setState(() => _error = r.error);
    if (r.body.isEmpty) return setState(() => _error = 'Nothing changed yet');
    Navigator.of(context).pop(r.body);
  }

  Widget _clearable(String key, String? currentValue, Widget field) {
    final c = MgColors.of(context);
    final has = currentValue != null && currentValue.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: field),
        if (has)
          IconButton(
            tooltip: _cleared.contains(key) ? 'Keep current value' : 'Remove current value',
            onPressed: () => setState(() => _cleared.contains(key) ? _cleared.remove(key) : _cleared.add(key)),
            icon: Icon(_cleared.contains(key) ? Icons.undo : Icons.backspace_outlined, color: _cleared.contains(key) ? c.danger : c.muted),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    final certs = _certs ?? p.certifications;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x2),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.form),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.admin ? 'Edit ${p.fullName}' : 'Edit your designation', style: t.titleLarge),
                const SizedBox(height: Space.xs),
                Text('Leave a field empty to keep it as it is.', style: t.bodySmall?.copyWith(color: c.muted)),
                const SizedBox(height: Space.lg),
                _clearable('designation', p.designation, MgTextField(controller: _designation, label: 'Designation', hint: _current(p.designation), maxLength: 60, textCapitalization: TextCapitalization.sentences)),
                if (widget.admin) ...[
                  _clearable('experienceYears', p.experienceYears?.toString(), MgTextField(controller: _experience, label: 'Experience (years)', hint: _current(p.experienceYears?.toString()), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 2)),
                  _clearable('phoneE164', p.phoneE164, MgTextField(controller: _phone, label: 'Contact phone (for SOS calls)', hint: _current(p.phoneE164), keyboardType: TextInputType.phone, maxLength: 18)),
                  _clearable('bloodGroup', p.bloodGroup, DropdownButtonFormField<String>(
                    initialValue: null,
                    decoration: InputDecoration(labelText: 'Blood group', helperText: _current(p.bloodGroup)),
                    items: [for (final b in bloodGroups) DropdownMenuItem(value: b, child: Text(b))],
                    onChanged: (v) => setState(() => _blood = v),
                  )),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: DropdownButtonFormField<Shift>(
                      initialValue: null,
                      decoration: InputDecoration(labelText: 'Shift', helperText: _current(p.shift == null ? null : '${p.shift!.wire} (${p.shift!.window})')),
                      items: [for (final s in Shift.values) DropdownMenuItem(value: s, child: Text('${s.wire} · ${s.window}'))],
                      onChanged: (v) => setState(() => _shift = v),
                    ),
                  ),
                  _clearable('medicalNotes', p.medicalNotes, MgTextField(controller: _medical, label: 'Medical notes (private)', hint: _current(p.medicalNotes), maxLines: 3, maxLength: 500)),
                  Text('Certifications', style: t.titleSmall),
                  const SizedBox(height: Space.sm),
                  Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                    for (final cert in certs)
                      InputChip(
                        label: Text(cert.expiresAt == null ? cert.name : '${cert.name} · ${DateFormat('d MMM y').format(cert.expiresAt!)}'),
                        onDeleted: () => setState(() => _certs = [...certs]..remove(cert)),
                      ),
                    if (certs.isEmpty) Text('None', style: t.bodySmall?.copyWith(color: c.muted)),
                  ]),
                  const SizedBox(height: Space.sm),
                  Row(children: [
                    Expanded(child: MgTextField(controller: _certName, label: 'New certification', maxLength: 80)),
                    const SizedBox(width: Space.sm),
                    IconButton(
                      tooltip: 'Expiry date',
                      icon: Icon(_certExpiry == null ? Icons.event : Icons.event_available, color: _certExpiry == null ? c.muted : c.success),
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 3650)), lastDate: now.add(const Duration(days: 3650)));
                        if (d != null) setState(() => _certExpiry = d);
                      },
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Add certification',
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final n = _certName.text.trim();
                        if (n.length < 2) return setState(() => _error = 'Certification name needs at least 2 characters');
                        setState(() {
                          _certs = [...certs, Certification(name: n, expiresAt: _certExpiry)];
                          _certName.clear();
                          _certExpiry = null;
                          _error = null;
                        });
                      },
                    ),
                  ]),
                  const SizedBox(height: Space.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Account active'),
                    subtitle: Text(_status == null ? 'Currently ${p.status}' : 'Will be set to $_status'),
                    value: (_status ?? p.status) == 'active',
                    onChanged: (v) => setState(() => _status = v ? 'active' : 'inactive'),
                  ),
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.sm), child: StatusChip(label: _error!, tone: ChipTone.danger, icon: Icons.error_outline)),
                const SizedBox(height: Space.lg),
                MgButton(label: 'Save changes', icon: Icons.check, expand: true, onPressed: _save),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
