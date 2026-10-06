import '../models/event.dart';

const registrationFieldTypes = {
  'text',
  'phone',
  'textarea',
  'select',
  'radio',
  'multiselect',
  'checkbox',
  'number',
  'file',
};

class RegistrationFormField {
  RegistrationFormField({
    required this.id,
    required this.type,
    required this.label,
    this.required = false,
    this.placeholder,
    this.options = const [],
  });

  final String id;
  final String type;
  final String label;
  final bool required;
  final String? placeholder;
  final List<String> options;

  factory RegistrationFormField.fromJson(Map<String, dynamic> json) {
    return RegistrationFormField(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? 'text').toString(),
      label: (json['label'] ?? '').toString(),
      required: json['required'] == true,
      placeholder: json['placeholder']?.toString(),
      options: (json['options'] is List)
          ? (json['options'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

class RegistrationFormSchema {
  RegistrationFormSchema({required this.fields, this.active = true});
  final List<RegistrationFormField> fields;
  final bool active;

  factory RegistrationFormSchema.fromJson(Map<String, dynamic> json) {
    final raw = json['fields'];
    if (raw is! List) return RegistrationFormSchema(fields: const []);
    final fields = raw
        .whereType<Map>()
        .map((e) => RegistrationFormField.fromJson(Map<String, dynamic>.from(e)))
        .where((f) =>
            f.id.isNotEmpty &&
            f.label.isNotEmpty &&
            registrationFieldTypes.contains(f.type))
        .toList();
    // Missing active defaults to true for backward compatibility.
    final active = json['active'] != false;
    return RegistrationFormSchema(fields: fields, active: active);
  }
}

class RegistrationFileAnswerRef {
  RegistrationFileAnswerRef({
    required this.uploadId,
    this.fileName,
    this.mimeType,
    this.size,
  });

  final String uploadId;
  final String? fileName;
  final String? mimeType;
  final int? size;

  Map<String, dynamic> toJson() => {
        'uploadId': uploadId,
        if (fileName != null) 'fileName': fileName,
        if (mimeType != null) 'mimeType': mimeType,
        if (size != null) 'size': size,
      };

  factory RegistrationFileAnswerRef.fromJson(Map<String, dynamic> json) {
    return RegistrationFileAnswerRef(
      uploadId: (json['uploadId'] ?? '').toString(),
      fileName: json['fileName']?.toString(),
      mimeType: json['mimeType']?.toString(),
      size: (json['size'] as num?)?.toInt(),
    );
  }
}

typedef RegistrationAnswers = Map<String, dynamic>;

bool isRegistrationFileAnswerRef(dynamic value) {
  if (value is! Map) return false;
  return (value['uploadId']?.toString().trim().isNotEmpty ?? false);
}

RegistrationFormSchema? getRegistrationFormFromEvent(Event event) {
  final other = event.otherInfo;
  dynamic raw = other?['registrationForm'];
  raw ??= other?['registration_form'];
  if (raw is! Map) return null;
  final schema = RegistrationFormSchema.fromJson(Map<String, dynamic>.from(raw));
  if (schema.fields.isEmpty) return null;
  // Inactive forms are not shown or required at checkout.
  if (!schema.active) return null;
  return schema;
}

bool isRegistrationFormSupportedForEvent(Event event) {
  if (event.hasSeatSelection) return false;
  return true;
}

bool _isEmpty(dynamic value) {
  if (value == null) return true;
  if (isRegistrationFileAnswerRef(value)) {
    return (value['uploadId']?.toString().trim().isEmpty ?? true);
  }
  if (value is String) return value.trim().isEmpty;
  if (value is bool) return value != true;
  if (value is List) {
    return value.every((item) => item == null || item.toString().trim().isEmpty);
  }
  return false;
}

List<String> asStringArray(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

({bool valid, Map<String, String> fieldErrors}) validateRegistrationAnswersClient(
  RegistrationFormSchema? form,
  RegistrationAnswers answers,
) {
  final fieldErrors = <String, String>{};
  if (form == null || form.fields.isEmpty) {
    return (valid: true, fieldErrors: fieldErrors);
  }

  for (final field in form.fields) {
    final raw = answers[field.id];
    if (field.type == 'file') {
      if (field.required && !isRegistrationFileAnswerRef(raw)) {
        fieldErrors[field.id] = 'Required';
      }
      continue;
    }
    if (field.type == 'checkbox') {
      if (field.required && raw != true) {
        fieldErrors[field.id] = 'Required';
      }
      continue;
    }
    if (field.type == 'multiselect') {
      final selected = asStringArray(raw);
      if (field.required && selected.isEmpty) {
        fieldErrors[field.id] = 'Select at least one option';
        continue;
      }
      if (field.options.isNotEmpty &&
          selected.any((item) => !field.options.contains(item))) {
        fieldErrors[field.id] = 'Select a valid option';
      }
      continue;
    }
    if (field.type == 'number') {
      if (_isEmpty(raw)) {
        if (field.required) fieldErrors[field.id] = 'Required';
        continue;
      }
      final parsed = double.tryParse(raw.toString());
      if (parsed == null || !parsed.isFinite) {
        fieldErrors[field.id] = 'Enter a valid number';
      }
      continue;
    }
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) {
      if (field.required) fieldErrors[field.id] = 'Required';
      continue;
    }
    if (field.type == 'phone' &&
        !RegExp(r'^[+]?[\d\s().-]{6,30}$').hasMatch(text)) {
      fieldErrors[field.id] = 'Enter a valid phone number';
    }
    if ((field.type == 'select' || field.type == 'radio') &&
        field.options.isNotEmpty &&
        !field.options.contains(text)) {
      fieldErrors[field.id] = 'Select a valid option';
    }
  }

  return (valid: fieldErrors.isEmpty, fieldErrors: fieldErrors);
}

RegistrationAnswers buildInitialRegistrationAnswers(RegistrationFormSchema? form) {
  final answers = <String, dynamic>{};
  if (form == null) return answers;
  for (final field in form.fields) {
    if (field.type == 'checkbox') {
      answers[field.id] = false;
    } else if (field.type == 'multiselect') {
      answers[field.id] = <String>[];
    } else if (field.type == 'file' || field.type == 'select' || field.type == 'radio') {
      answers[field.id] = null;
    } else {
      answers[field.id] = '';
    }
  }
  return answers;
}

const registrationFileMaxBytes = 5 * 1024 * 1024;

Map<String, dynamic>? serializeRegistrationAnswers(RegistrationAnswers? answers) {
  if (answers == null || answers.isEmpty) return null;
  final out = <String, dynamic>{};
  for (final entry in answers.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    if (value is bool && value != true) continue;
    if (value is List) {
      final selected = asStringArray(value);
      if (selected.isEmpty) continue;
      out[entry.key] = selected;
      continue;
    }
    if (isRegistrationFileAnswerRef(value)) {
      out[entry.key] = Map<String, dynamic>.from(value as Map);
      continue;
    }
    out[entry.key] = value;
  }
  return out.isEmpty ? null : out;
}

List<Map<String, dynamic>>? registrationFormFieldsForPayload(RegistrationFormSchema? form) {
  if (form == null || form.fields.isEmpty) return null;
  return form.fields
      .map((f) => {
            'id': f.id,
            'type': f.type,
            'label': f.label,
            'required': f.required,
            if (f.placeholder != null) 'placeholder': f.placeholder,
            if (f.options.isNotEmpty) 'options': f.options,
          })
      .toList();
}

RegistrationFormSchema? registrationFormFromPayloadFields(List<Map<String, dynamic>>? fields) {
  if (fields == null || fields.isEmpty) return null;
  final schema = RegistrationFormSchema.fromJson({'fields': fields});
  return schema.fields.isEmpty ? null : schema;
}
