/// A single SponsorBlock segment retrieved from the public API.
///
/// Only the fields needed for client-side skip logic are stored.
/// Category strings match the SponsorBlock API spec:
///   sponsor, selfpromo, interaction, intro, outro, preview,
///   music_offtopic, filler
class SponsorSegment {
  /// Start time in seconds.
  final double start;

  /// End time in seconds.
  final double end;

  /// SponsorBlock category string (e.g. "sponsor", "intro").
  final String category;

  /// Unique segment UUID — used to deduplicate skips and report views.
  final String uuid;

  const SponsorSegment({
    required this.start,
    required this.end,
    required this.category,
    required this.uuid,
  });

  factory SponsorSegment.fromJson(Map<String, dynamic> j) {
    final seg = j['segment'];
    double start = 0;
    double end = 0;
    if (seg is List && seg.length >= 2) {
      start = (seg[0] as num).toDouble();
      end = (seg[1] as num).toDouble();
    }
    return SponsorSegment(
      start: start,
      end: end,
      category: j['category']?.toString() ?? 'sponsor',
      uuid: j['UUID']?.toString() ?? '',
    );
  }

  /// All human-readable category display names, used in Settings UI.
  static const Map<String, String> categoryLabels = {
    'sponsor': 'Paid Promotion',
    'selfpromo': 'Self-Promotion',
    'interaction': 'Interaction Reminder',
    'intro': 'Intro / Intermission',
    'outro': 'Outro / Credits',
    'preview': 'Preview',
    'music_offtopic': 'Off-Topic Music',
    'filler': 'Filler Tangent',
  };

  static const List<String> allCategories = [
    'sponsor',
    'selfpromo',
    'interaction',
    'intro',
    'outro',
    'preview',
    'music_offtopic',
    'filler',
  ];
}
