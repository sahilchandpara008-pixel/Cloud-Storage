import 'config.dart';

class UserStatus {
  final String userId;
  final String displayName;
  final bool isGuest;
  final String source; // ads | organic
  final bool isPremium;
  final bool hasAdsAccess;
  final String? planName;
  final DateTime? planEndsAt;
  final int usedBytes;
  final int quotaBytes;
  final String? openRequest;
  final bool freeMode; // app is free: no plans, approval flow only
  final String accessStatus; // none | pending | approved | rejected

  const UserStatus({
    required this.userId,
    required this.displayName,
    required this.isGuest,
    required this.source,
    required this.isPremium,
    this.hasAdsAccess = false,
    this.planName,
    this.planEndsAt,
    this.usedBytes = 0,
    this.quotaBytes = 0,
    this.openRequest,
    this.freeMode = false,
    this.accessStatus = 'none',
  });

  factory UserStatus.fromJson(Map<String, dynamic> j) => UserStatus(
    userId: j['user_id'] as String,
    displayName: (j['display_name'] as String?) ?? 'User',
    isGuest: (j['is_guest'] as bool?) ?? true,
    source: (j['source'] as String?) ?? 'organic',
    isPremium: (j['is_premium'] as bool?) ?? false,
    hasAdsAccess: (j['has_ads_access'] as bool?) ?? false,
    planName: j['plan_name'] as String?,
    planEndsAt: j['plan_ends_at'] == null
        ? null
        : DateTime.parse(j['plan_ends_at'] as String),
    usedBytes: (j['used_bytes'] as num?)?.toInt() ?? 0,
    quotaBytes: (j['quota_bytes'] as num?)?.toInt() ?? 0,
    openRequest: j['open_request'] as String?,
    freeMode: (j['free_mode'] as bool?) ?? false,
    accessStatus: (j['access_status'] as String?) ?? 'none',
  );
}

class Channel {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final String? iconUrl;
  final int membersCount;
  final int foldersCount;
  final String reviewStatus; // pending | approved | rejected
  final String? createdBy;

  const Channel({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.iconUrl,
    this.membersCount = 0,
    this.foldersCount = 0,
    this.reviewStatus = 'approved',
    this.createdBy,
  });

  factory Channel.fromJson(Map<String, dynamic> j) {
    final folders = j['channel_folders'];
    return Channel(
      id: j['id'] as String,
      name: j['name'] as String,
      description: j['description'] as String?,
      category: j['category'] as String?,
      iconUrl: j['icon_url'] as String?,
      membersCount: (j['members_count'] as num?)?.toInt() ?? 0,
      foldersCount: folders is List && folders.isNotEmpty
          ? ((folders.first['count'] as num?)?.toInt() ?? 0)
          : 0,
      reviewStatus: (j['review_status'] as String?) ?? 'approved',
      createdBy: j['created_by'] as String?,
    );
  }
}

class Folder {
  final String id;
  final String name;
  const Folder(this.id, this.name);
}

class PostItem {
  final String id;
  final String kind; // video | image
  final bool isPremium;

  /// Null for a video that streams from Bunny instead of Supabase Storage
  /// (see [isBunnyBacked]); always set otherwise.
  final String? mediaKey;
  final String? thumbKey;
  final String? trailerKey;

  /// The database's "has a playable trailer" flag. True for a trailer file in
  /// Supabase Storage ([trailerKey]) and for a preview stored on Bunny, which
  /// has no key the app can read.
  final bool trailerReady;
  final int? durationS;
  final int position;

  const PostItem({
    required this.id,
    required this.kind,
    required this.isPremium,
    this.mediaKey,
    this.thumbKey,
    this.trailerKey,
    this.trailerReady = false,
    this.durationS,
    this.position = 0,
  });

  bool get hasTrailer => trailerKey != null || trailerReady;

  /// A preview streamed from Bunny (no readable key, see [trailerReady]).
  bool get trailerOnBunny => trailerKey == null && trailerReady;
  bool get isVideo => kind == 'video';
  bool get isBunnyBacked => mediaKey == null;
  String? get thumbUrl => thumbKey == null ? null : Config.publicUrl(thumbKey!);

  factory PostItem.fromJson(Map<String, dynamic> j) => PostItem(
    id: j['id'] as String,
    kind: j['kind'] as String,
    isPremium: (j['is_premium'] as bool?) ?? false,
    mediaKey: j['media_key'] as String?,
    thumbKey: j['thumb_key'] as String?,
    trailerKey: j['trailer_key'] as String?,
    trailerReady: (j['has_trailer'] as bool?) ?? false,
    durationS: (j['duration_s'] as num?)?.toInt(),
    position: (j['position'] as num?)?.toInt() ?? 0,
  );
}

class Post {
  final String id;
  final String channelId;
  final String? createdBy;
  final String? folderId;
  final String channelName;
  final String? channelIcon;
  final String title;
  final String? caption;
  final DateTime publishedAt;
  final int viewCount;
  final List<PostItem> items;

  const Post({
    required this.id,
    required this.channelId,
    this.createdBy,
    this.folderId,
    required this.channelName,
    this.channelIcon,
    required this.title,
    this.caption,
    required this.publishedAt,
    this.viewCount = 0,
    this.items = const [],
  });

  PostItem? get cover => items.isEmpty ? null : items.first;
  bool get hasPremium => items.any((i) => i.isPremium);

  static const select =
      '*, channels(name, icon_url), post_items(id, kind, is_premium, media_key, thumb_key, trailer_key, has_trailer, duration_s, position)';

  factory Post.fromJson(Map<String, dynamic> j) {
    final ch = j['channels'] as Map<String, dynamic>?;
    final items =
        ((j['post_items'] as List?) ?? [])
            .map((e) => PostItem.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return Post(
      id: j['id'] as String,
      channelId: j['channel_id'] as String,
      createdBy: j['created_by'] as String?,
      folderId: j['folder_id'] as String?,
      channelName: (ch?['name'] as String?) ?? '',
      channelIcon: ch?['icon_url'] as String?,
      title: j['title'] as String,
      caption: j['caption'] as String?,
      publishedAt: DateTime.parse(
        (j['published_at'] ?? j['created_at']) as String,
      ).toLocal(),
      viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }
}

class Plan {
  final String id;
  final String code;
  final String name;
  final int durationDays;
  final int priceInr;
  final List<String> perks;

  /// Set in admin → Plans: pre-selected and shown as "Most popular".
  final bool recommended;

  const Plan({
    required this.id,
    required this.code,
    required this.name,
    required this.durationDays,
    required this.priceInr,
    this.perks = const [],
    this.recommended = false,
  });

  String get durationLabel {
    if (durationDays % 365 == 0) {
      return durationDays == 365 ? '1 Year' : '${durationDays ~/ 365} Years';
    }
    if (durationDays % 30 == 0) {
      return durationDays == 30 ? '1 Month' : '${durationDays ~/ 30} Months';
    }
    if (durationDays == 7) return '7 Days';
    return '$durationDays Days';
  }

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
    id: j['id'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
    durationDays: (j['duration_days'] as num).toInt(),
    priceInr: (j['price_inr'] as num).toInt(),
    perks: ((j['perks'] as List?) ?? []).map((e) => e.toString()).toList(),
    recommended: j['recommended'] == true,
  );
}

class CloudFile {
  final String id;
  final String? parentId;
  final String name;
  final bool isFolder;
  final String? storageKey;

  /// Set instead of [storageKey] for a file saved on Bunny Storage.
  final String? bunnyPath;
  final String? mime;
  final int size;
  final DateTime createdAt;

  const CloudFile({
    required this.id,
    this.parentId,
    required this.name,
    required this.isFolder,
    this.storageKey,
    this.bunnyPath,
    this.mime,
    this.size = 0,
    required this.createdAt,
  });

  bool get isImage => (mime ?? '').startsWith('image/');
  bool get isVideo => (mime ?? '').startsWith('video/');
  bool get isBunnyBacked => bunnyPath != null;

  factory CloudFile.fromJson(Map<String, dynamic> j) => CloudFile(
    id: j['id'] as String,
    parentId: j['parent_id'] as String?,
    name: j['name'] as String,
    isFolder: j['is_folder'] as bool,
    storageKey: j['storage_key'] as String?,
    bunnyPath: j['bunny_path'] as String?,
    mime: j['mime'] as String?,
    size: (j['size'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

/// A UPI payment order (read-only for the app; only server functions change it).
class PaymentOrder {
  final String id;
  final String reference;
  final int amountPaise;
  final String
  status; // initiated | pending | approved | failed | cancelled | revoked
  final String? clientStatus;
  final String? txnId;
  final String? planName;
  final DateTime createdAt;
  final DateTime? verifiedAt;

  const PaymentOrder({
    required this.id,
    required this.reference,
    required this.amountPaise,
    required this.status,
    required this.createdAt,
    this.clientStatus,
    this.txnId,
    this.planName,
    this.verifiedAt,
  });

  static const select =
      'id, reference, amount_paise, status, client_status, txn_id, created_at, verified_at, plans(name)';

  bool get isOpen => status == 'initiated' || status == 'pending';
  String get amountLabel => '₹${(amountPaise / 100).toStringAsFixed(2)}';

  factory PaymentOrder.fromJson(Map<String, dynamic> j) => PaymentOrder(
    id: j['id'] as String,
    reference: j['reference'] as String,
    amountPaise: (j['amount_paise'] as num).toInt(),
    status: j['status'] as String,
    clientStatus: j['client_status'] as String?,
    txnId: j['txn_id'] as String?,
    planName: (j['plans'] as Map?)?['name'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    verifiedAt: j['verified_at'] == null
        ? null
        : DateTime.parse(j['verified_at'] as String),
  );
}
