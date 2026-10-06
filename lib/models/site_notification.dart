/// CMS site notice (same payload shape as web `notification` array on GET /front home).
class SiteNotification {
  final String id;
  final String notificationHtml;
  final String? notificationTypeName;

  const SiteNotification({
    required this.id,
    required this.notificationHtml,
    this.notificationTypeName,
  });

  factory SiteNotification.fromJson(Map<String, dynamic> json) {
    final idRaw = json['_id'];
    final id = idRaw == null ? '' : idRaw.toString();
    final type = json['notificationType'];
    String? typeName;
    if (type is Map) {
      typeName = type['name']?.toString();
    }
    final raw = json['notification'];
    return SiteNotification(
      id: id,
      notificationHtml: raw == null ? '' : raw.toString(),
      notificationTypeName: typeName,
    );
  }
}
