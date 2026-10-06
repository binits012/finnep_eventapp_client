import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/registration_upload_service.dart';
import '../utils/registration_form.dart';

class RegistrationFormFields extends StatefulWidget {
  const RegistrationFormFields({
    super.key,
    required this.eventId,
    required this.fields,
    required this.answers,
    required this.fieldErrors,
    required this.onChanged,
    this.disabled = false,
    this.onUploadingChange,
  });

  final String eventId;
  final List<RegistrationFormField> fields;
  final RegistrationAnswers answers;
  final Map<String, String> fieldErrors;
  final void Function(String fieldId, dynamic value) onChanged;
  final bool disabled;
  final void Function(bool uploading)? onUploadingChange;

  @override
  State<RegistrationFormFields> createState() => _RegistrationFormFieldsState();
}

class _RegistrationFormFieldsState extends State<RegistrationFormFields> {
  String? _uploadingFieldId;
  final Map<String, String> _uploadErrors = {};
  final Map<String, TextEditingController> _textControllers = {};

  bool _isTextFieldType(String type) =>
      type == 'text' ||
      type == 'phone' ||
      type == 'textarea' ||
      type == 'number';

  @override
  void initState() {
    super.initState();
    _syncTextControllers(force: true);
  }

  @override
  void didUpdateWidget(covariant RegistrationFormFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.fields.map((f) => f.id).join('|');
    final newIds = widget.fields.map((f) => f.id).join('|');
    if (oldIds != newIds) {
      _syncTextControllers(force: true);
    }
  }

  void _syncTextControllers({required bool force}) {
    final activeIds = widget.fields
        .where((f) => _isTextFieldType(f.type))
        .map((f) => f.id)
        .toSet();

    for (final id in _textControllers.keys.toList()) {
      if (!activeIds.contains(id)) {
        _textControllers.remove(id)?.dispose();
      }
    }

    for (final field in widget.fields) {
      if (!_isTextFieldType(field.type)) continue;
      final initial = widget.answers[field.id]?.toString() ?? '';
      final existing = _textControllers[field.id];
      if (existing == null) {
        _textControllers[field.id] = TextEditingController(text: initial);
      } else if (force && existing.text != initial) {
        existing.text = initial;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _setUploading(String? fieldId) async {
    setState(() => _uploadingFieldId = fieldId);
    widget.onUploadingChange?.call(fieldId != null);
  }

  Future<void> _pickFile(RegistrationFormField field) async {
    if (widget.disabled || _uploadingFieldId != null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    var bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      setState(() => _uploadErrors[field.id] = 'Could not read file');
      return;
    }
    if (bytes.length > registrationFileMaxBytes) {
      setState(() => _uploadErrors[field.id] = 'File too large (max 5 MB)');
      return;
    }

    final fileName = file.name.trim().isNotEmpty ? file.name.trim() : 'upload';
    final mime = _mimeFromName(fileName);
    await _setUploading(field.id);
    setState(() => _uploadErrors.remove(field.id));
    try {
      final uploaded = await uploadRegistrationFile(
        eventId: widget.eventId,
        fieldId: field.id,
        bytes: bytes,
        fileName: fileName,
        mimeType: mime,
      );
      widget.onChanged(field.id, uploaded.toJson());
    } catch (e) {
      setState(() => _uploadErrors[field.id] = e.toString().replaceFirst('ApiException(', '').replaceAll(')', ''));
    } finally {
      await _setUploading(null);
    }
  }

  Future<void> _removeFile(RegistrationFormField field) async {
    final raw = widget.answers[field.id];
    if (!isRegistrationFileAnswerRef(raw)) {
      widget.onChanged(field.id, null);
      return;
    }
    final uploadId = raw['uploadId']?.toString() ?? '';
    if (uploadId.isEmpty) {
      widget.onChanged(field.id, null);
      return;
    }
    await _setUploading(field.id);
    try {
      await deleteRegistrationUpload(eventId: widget.eventId, uploadId: uploadId);
      widget.onChanged(field.id, null);
    } catch (_) {
      widget.onChanged(field.id, null);
    } finally {
      await _setUploading(null);
    }
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fields.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in widget.fields) ...[
          _buildField(context, field),
          if (widget.fieldErrors[field.id] != null ||
              _uploadErrors[field.id] != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.fieldErrors[field.id] ?? _uploadErrors[field.id] ?? '',
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildField(BuildContext context, RegistrationFormField field) {
    final errorText = widget.fieldErrors[field.id] ?? _uploadErrors[field.id];
    final border = OutlineInputBorder(
      borderSide: BorderSide(
        color: errorText != null
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).dividerColor,
      ),
    );

    switch (field.type) {
      case 'checkbox':
        return CheckboxListTile(
          key: ValueKey(field.id),
          value: widget.answers[field.id] == true,
          onChanged: widget.disabled
              ? null
              : (v) => widget.onChanged(field.id, v == true),
          title: Text(field.label + (field.required ? ' *' : '')),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        );
      case 'select':
        final options = field.options
            .map((o) => o.trim())
            .where((o) => o.isNotEmpty)
            .toList();
        if (options.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: field.label + (field.required ? ' *' : ''),
              border: border,
              enabled: false,
            ),
            child: Text(
              'No options configured',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        final raw = widget.answers[field.id]?.toString();
        final selected = (raw != null && raw.isNotEmpty && options.contains(raw))
            ? raw
            : null;
        final fieldStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
              inherit: false,
              fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16,
            ) ??
            const TextStyle(fontSize: 16, inherit: false);
        return DropdownButtonFormField<String>(
          key: ValueKey(field.id),
          value: selected,
          isDense: false,
          isExpanded: true,
          style: fieldStyle,
          decoration: InputDecoration(
            labelText: field.label + (field.required ? ' *' : ''),
            border: border,
          ),
          hint: Text(
            field.placeholder ?? 'Select…',
            style: fieldStyle.copyWith(
              color: Theme.of(context).hintColor,
            ),
          ),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: widget.disabled
              ? null
              : (v) => widget.onChanged(field.id, v ?? ''),
        );
      case 'radio':
        final radioOptions = field.options
            .map((o) => o.trim())
            .where((o) => o.isNotEmpty)
            .toList();
        final radioRaw = widget.answers[field.id]?.toString();
        final radioSelected =
            (radioRaw != null && radioRaw.isNotEmpty && radioOptions.contains(radioRaw))
                ? radioRaw
                : null;
        return InputDecorator(
          key: ValueKey(field.id),
          decoration: InputDecoration(
            labelText: field.label + (field.required ? ' *' : ''),
            border: border,
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          ),
          child: radioOptions.isEmpty
              ? Text(
                  'No options configured',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Column(
                  children: [
                    for (final opt in radioOptions)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(opt),
                        value: opt,
                        groupValue: radioSelected,
                        onChanged: widget.disabled
                            ? null
                            : (v) => widget.onChanged(field.id, v ?? ''),
                      ),
                  ],
                ),
        );
      case 'multiselect':
        final multiOptions = field.options
            .map((o) => o.trim())
            .where((o) => o.isNotEmpty)
            .toList();
        final selected = asStringArray(widget.answers[field.id]);
        return InputDecorator(
          key: ValueKey(field.id),
          decoration: InputDecoration(
            labelText: field.label + (field.required ? ' *' : ''),
            border: border,
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          ),
          child: multiOptions.isEmpty
              ? Text(
                  'No options configured',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Column(
                  children: [
                    for (final opt in multiOptions)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(opt),
                        value: selected.contains(opt),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: widget.disabled
                            ? null
                            : (checked) {
                                final next = List<String>.from(selected);
                                if (checked == true) {
                                  if (!next.contains(opt)) next.add(opt);
                                } else {
                                  next.remove(opt);
                                }
                                widget.onChanged(field.id, next);
                              },
                      ),
                  ],
                ),
        );
      case 'textarea':
        return TextFormField(
          key: ValueKey(field.id),
          controller: _textControllers[field.id],
          maxLines: 3,
          enabled: !widget.disabled,
          decoration: InputDecoration(
            labelText: field.label + (field.required ? ' *' : ''),
            hintText: field.placeholder,
            border: border,
          ),
          onChanged: (v) => widget.onChanged(field.id, v),
        );
      case 'file':
        final raw = widget.answers[field.id];
        final fileName = isRegistrationFileAnswerRef(raw)
            ? raw['fileName']?.toString() ?? 'Uploaded file'
            : null;
        final busy = _uploadingFieldId == field.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label + (field.required ? ' *' : ''),
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (fileName != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.disabled || busy ? null : () => _removeFile(field),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: widget.disabled || busy ? null : () => _pickFile(field),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(busy ? 'Uploading…' : 'Choose file'),
              ),
          ],
        );
      default:
        return TextFormField(
          key: ValueKey(field.id),
          controller: _textControllers[field.id],
          enabled: !widget.disabled,
          keyboardType: field.type == 'phone'
              ? TextInputType.phone
              : field.type == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
          decoration: InputDecoration(
            labelText: field.label + (field.required ? ' *' : ''),
            hintText: field.placeholder,
            border: border,
          ),
          onChanged: (v) => widget.onChanged(field.id, v),
        );
    }
  }
}
