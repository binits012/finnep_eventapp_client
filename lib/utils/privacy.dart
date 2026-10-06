String maskEmailForDisplay(String email) {
  final value = email.trim();
  final atIndex = value.indexOf('@');
  if (value.isEmpty || atIndex <= 0 || atIndex != value.lastIndexOf('@')) {
    return value;
  }

  final local = value.substring(0, atIndex);
  final domain = value.substring(atIndex + 1);
  if (domain.isEmpty) return '${_maskPart(local)}@';

  final domainParts = domain.split('.');
  final domainName = domainParts.first;
  final suffix = domainParts.length > 1
      ? '.${domainParts.skip(1).join('.')}'
      : '';

  return '${_maskPart(local)}@${_maskPart(domainName)}$suffix';
}

String _maskPart(String value) {
  if (value.isEmpty) return '';
  if (value.length == 1) return '${value[0]}***';
  return '${value[0]}***${value[value.length - 1]}';
}
