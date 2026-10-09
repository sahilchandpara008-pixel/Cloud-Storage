import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'blocks.dart';

SupabaseClient get sb => Supabase.instance.client;
const _uuid = Uuid();

/// All data access. Every rule (audience, premium, approvals) is enforced by
/// the database, so these calls just ask for data and report errors.
class Backend {
  // ---------------------------------------------------------------- status
  static Future<UserStatus?> status() async {
    final res = await sb.rpc('my_status');
    if (res == null) return null;
    return UserStatus.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Google Play build only: 15 GB of free cloud storage after login.
  static Future<void> enablePlayFreeCloud() => sb.rpc('enable_play_free_cloud');

  static Future<String?> recordInstall(
    String installId,
    String status,
    String? referrer,
  ) async {
    final res = await sb.rpc(
      'record_install',
      params: {
        'p_install_id': installId,
        'p_referrer_status': status,
        'p_referrer': referrer,
        'p_install_ts': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return res as String?;
  }

  static Future<void> attributeUser(String installId) async {
    await sb.rpc('attribute_user', params: {'p_install_id': installId});
  }

  static Future<void> logEvent(
    String installId,
    String event, {
    String? contentId,
    String? viewId,
  }) async {
    try {
      await sb.rpc(
        'log_event',
        params: {
          'p_install_id': installId,
          'p_event': event,
          'p_content_id': contentId,
          'p_view_id': viewId,
        },
      );
    } catch (_) {
      // Analytics must never break the app.
    }
  }

  static Future<void> saveConsent(String version) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    await sb.from('consents').insert({
      'user_id': uid,
      'policy_version': version,
    });
  }

  // ---------------------------------------------------------------- content
  static Future<List<Post>> explore(String tab, {int offset = 0}) async {
    final rows = await sb
        .rpc(
          'explore',
          params: {'p_tab': tab, 'p_limit': 30, 'p_offset': offset},
        )
        .select(Post.select);
    return (rows as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .where((p) => !Blocks.has(p.channelId))
        .toList();
  }

  static Future<List<Post>> feed({DateTime? before}) async {
    final rows = await sb
        .rpc(
          'feed',
          params: {
            'p_before': before?.toUtc().toIso8601String(),
            'p_limit': 30,
          },
        )
        .select(Post.select);
    return (rows as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .where((p) => !Blocks.has(p.channelId))
        .toList();
  }

  static Future<List<Post>> channelPosts(
    String channelId, {
    DateTime? before,
  }) async {
    final rows = await sb
        .rpc(
          'channel_posts',
          params: {
            'p_channel_id': channelId,
            'p_before': before?.toUtc().toIso8601String(),
            'p_limit': 50,
          },
        )
        .select(Post.select);
    return (rows as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Post?> post(String id) async {
    final row = await sb
        .from('posts')
        .select(Post.select)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Post.fromJson(row);
  }

  /// Other posts by the same uploader ("More from this creator"). The
  /// database still decides what this user may see (audience, approval).
  static Future<List<Post>> moreFromCreator(Post post) async {
    var q = sb
        .from('posts')
        .select(Post.select)
        .eq('status', 'published')
        .lte('published_at', DateTime.now().toUtc().toIso8601String())
        .neq('id', post.id);
    q = post.createdBy != null
        ? q.eq('created_by', post.createdBy!)
        : q.eq('channel_id', post.channelId);
    final rows = await q.order('published_at', ascending: false).limit(30);
    return rows.map(Post.fromJson).toList();
  }

  static const _channelSelect =
      'id, name, description, category, icon_url, members_count, review_status, created_by, created_at, channel_folders(count)';

  /// sort: trending | latest | top
  static Future<List<Channel>> channels({
    String sort = 'trending',
    String? search,
  }) async {
    var q = sb
        .from('channels')
        .select(_channelSelect)
        .eq('review_status', 'approved')
        .eq('status', 'published');
    if (search != null && search.trim().isNotEmpty) {
      q = q.ilike('name', '%${search.trim()}%');
    }
    final column = switch (sort) {
      'latest' => 'created_at',
      'top' => 'rating',
      _ => 'members_count',
    };
    final rows = await q.order(column, ascending: false).limit(100);
    return rows.map(Channel.fromJson).where((c) => !Blocks.has(c.id)).toList();
  }

  static Future<Channel?> channel(String id) async {
    final row = await sb
        .from('channels')
        .select(_channelSelect)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Channel.fromJson(row);
  }

  static Future<List<Channel>> myCreatedChannels() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await sb
        .from('channels')
        .select(_channelSelect)
        .eq('created_by', uid)
        .order('created_at', ascending: false);
    return rows.map(Channel.fromJson).toList();
  }

  static Future<Set<String>> joinedChannelIds() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await sb
        .from('channel_members')
        .select('channel_id')
        .eq('user_id', uid);
    return rows.map((r) => r['channel_id'] as String).toSet();
  }

  static Future<List<Channel>> joinedChannels() async {
    final ids = await joinedChannelIds();
    if (ids.isEmpty) return [];
    final rows = await sb
        .from('channels')
        .select(_channelSelect)
        .inFilter('id', ids.toList())
        .order('name', ascending: true);
    return rows.map(Channel.fromJson).toList();
  }

  static Future<void> join(String channelId) async {
    await sb.from('channel_members').insert({
      'channel_id': channelId,
      'user_id': sb.auth.currentUser!.id,
    });
  }

  static Future<void> leave(String channelId) async {
    await sb
        .from('channel_members')
        .delete()
        .eq('channel_id', channelId)
        .eq('user_id', sb.auth.currentUser!.id);
  }

  static Future<List<Folder>> folders(String channelId) async {
    final rows = await sb
        .from('channel_folders')
        .select('id, name')
        .eq('channel_id', channelId)
        .order('position', ascending: true);
    return rows
        .map((r) => Folder(r['id'] as String, r['name'] as String))
        .toList();
  }

  /// Short-lived link to play a media file. The storage rules refuse it unless
  /// the post is visible to the user and the item is free or they're premium.
  static Future<String> mediaUrl(String key) =>
      sb.storage.from('media').createSignedUrl(key, 60 * 60);

  // ---------------------------------------------------------------- creators
  static Future<String> uploadChannelIcon(
    Uint8List bytes,
    String ext,
    String mime,
  ) async {
    final key = 'channels/${sb.auth.currentUser!.id}/${_uuid.v4()}.$ext';
    await sb.storage
        .from('public')
        .uploadBinary(key, bytes, fileOptions: FileOptions(contentType: mime));
    return sb.storage.from('public').getPublicUrl(key);
  }

  /// The creator changes their channel's photo (the database only lets the
  /// creator or an admin change it).
  static Future<void> updateChannelIcon(
    String channelId,
    String iconUrl,
  ) async {
    await sb.from('channels').update({'icon_url': iconUrl}).eq('id', channelId);
  }

  static Future<Channel> createChannel({
    required String name,
    String? description,
    String? category,
    String? iconUrl,
  }) async {
    final row = await sb
        .from('channels')
        .insert({
          'name': name,
          'description': description,
          'category': category,
          'icon_url': iconUrl,
        })
        .select(_channelSelect)
        .single();
    return Channel.fromJson(row);
  }

  static Future<Folder> createChannelFolder(
    String channelId,
    String name,
    int position,
  ) async {
    final row = await sb
        .from('channel_folders')
        .insert({'channel_id': channelId, 'name': name, 'position': position})
        .select('id, name')
        .single();
    return Folder(row['id'] as String, row['name'] as String);
  }

  static Future<String> createPost(
    String channelId,
    String title,
    String? caption, {
    String? folderId,
  }) async {
    final row = await sb
        .from('posts')
        .insert({
          'channel_id': channelId,
          'folder_id': folderId,
          'title': title,
          'caption': caption,
          'status': 'published',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> addPostItem({
    required String postId,
    required int position,
    required String kind,
    required Uint8List bytes,
    required String ext,
    required String mime,
    Uint8List? thumbnail,
    Uint8List? trailerBytes,
    String? trailerExt,
    String? trailerMime,
  }) async {
    final id = _uuid.v4();
    final mediaKey = 'posts/$postId/$id.$ext';
    await sb.storage
        .from('media')
        .uploadBinary(
          mediaKey,
          bytes,
          fileOptions: FileOptions(contentType: mime),
        );
    String? thumbKey;
    if (thumbnail != null) {
      thumbKey = 'thumbs/$postId/$id.jpg';
      await sb.storage
          .from('public')
          .uploadBinary(
            thumbKey,
            thumbnail,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    }
    String? trailerKey;
    if (trailerBytes != null) {
      trailerKey = 'posts/$postId/$id-trailer.${trailerExt ?? 'mp4'}';
      await sb.storage
          .from('media')
          .uploadBinary(
            trailerKey,
            trailerBytes,
            fileOptions: FileOptions(contentType: trailerMime ?? 'video/mp4'),
          );
    }
    await sb.from('post_items').insert({
      'post_id': postId,
      'position': position,
      'kind': kind,
      'media_key': mediaKey,
      'thumb_key': thumbKey,
      'trailer_key': trailerKey,
      'processing_status': 'ready',
    });
  }

  static Future<void> deletePost(String postId) async {
    await sb.from('posts').delete().eq('id', postId);
  }

  // ---------------------------------------------------------------- plans
  static Future<List<Plan>> plans() async {
    final rows = await sb
        .from('plans')
        .select()
        .eq('active', true)
        .order('position', ascending: true);
    return rows.map(Plan.fromJson).toList();
  }

  static Future<void> requestPlan(String planId) async {
    await sb.from('plan_requests').insert({'plan_id': planId});
  }

  // ---------------------------------------------------------------- payments
  /// Server creates (or reuses) the order; the amount comes from the plans table.
  static Future<Map<String, dynamic>> createPaymentOrder(String planId) async {
    final res = await sb.rpc(
      'create_payment_order',
      params: {'p_plan_id': planId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Sends the UPI app's raw answer; the server decides what it means.
  /// Play build: keep Google's transaction token with the order so the server
  /// can report the payment to Google Play once it is approved.
  static Future<void> attachPlayToken(String orderId, String token) async {
    await sb.rpc(
      'attach_play_token',
      params: {'p_order_id': orderId, 'p_token': token},
    );
  }

  /// Report a post or channel to the Flixvault team.
  static Future<void> reportContent({
    String? postId,
    String? channelId,
    required String reason,
    String? details,
  }) async {
    await sb.rpc(
      'report_content_in_app',
      params: {
        'p_post_id': postId,
        'p_channel_id': channelId,
        'p_reason': reason,
        'p_details': details,
      },
    );
  }

  static Future<Map<String, dynamic>> reportPaymentResult(
    String orderId,
    String raw,
  ) async {
    final res = await sb.rpc(
      'report_payment_result',
      params: {'p_order_id': orderId, 'p_raw': raw},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<PaymentOrder?> paymentOrder(String orderId) async {
    final row = await sb
        .from('payment_orders')
        .select(PaymentOrder.select)
        .eq('id', orderId)
        .maybeSingle();
    return row == null ? null : PaymentOrder.fromJson(row);
  }

  static Future<List<PaymentOrder>> paymentHistory() async {
    final rows = await sb
        .from('payment_orders')
        .select(PaymentOrder.select)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(PaymentOrder.fromJson).toList();
  }

  // ---------------------------------------------------------------- cloud
  static Future<List<CloudFile>> cloudFiles(String? parentId) async {
    var q = sb.from('cloud_files').select();
    q = parentId == null
        ? q.isFilter('parent_id', null)
        : q.eq('parent_id', parentId);
    final rows = await q
        .order('is_folder', ascending: false)
        .order('name', ascending: true);
    return rows.map(CloudFile.fromJson).toList();
  }

  static Future<void> createFolder(String? parentId, String name) async {
    await sb.from('cloud_files').insert({
      'parent_id': parentId,
      'name': name,
      'is_folder': true,
    });
  }

  static Future<void> uploadCloudFile(
    String? parentId,
    String name,
    Uint8List bytes,
    String? mime,
  ) async {
    final uid = sb.auth.currentUser!.id;
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final key = '$uid/${_uuid.v4()}-$safe';
    await sb.storage
        .from('cloud')
        .uploadBinary(key, bytes, fileOptions: FileOptions(contentType: mime));
    try {
      await sb.from('cloud_files').insert({
        'parent_id': parentId,
        'name': name,
        'storage_key': key,
        'mime': mime,
        'size': bytes.length,
      });
    } catch (e) {
      await sb.storage.from('cloud').remove([key]); // e.g. quota exceeded
      rethrow;
    }
  }

  static Future<String> cloudUrl(String key) =>
      sb.storage.from('cloud').createSignedUrl(key, 60 * 60);

  static Future<void> renameCloudFile(String id, String name) async {
    await sb.from('cloud_files').update({'name': name}).eq('id', id);
  }

  static Future<void> deleteCloudFile(CloudFile f) async {
    final keys = f.isFolder
        ? ((await sb.rpc(
            'cloud_folder_keys',
            params: {'p_folder_id': f.id},
          )) as List).cast<String>()
        : [f.storageKey!];
    for (var i = 0; i < keys.length; i += 100) {
      await sb.storage
          .from('cloud')
          .remove(
            keys.sublist(i, i + 100 > keys.length ? keys.length : i + 100),
          );
    }
    await sb.from('cloud_files').delete().eq('id', f.id);
  }

  // ---------------------------------------------------------------- profile
  static Future<void> updateName(String name) async {
    await sb
        .from('profiles')
        .update({'display_name': name})
        .eq('id', sb.auth.currentUser!.id);
  }

  static Future<void> deleteAccount() async {
    final res = await sb.functions.invoke(
      'delete-account',
      method: HttpMethod.post,
    );
    if (res.status != 200) {
      throw Exception(
        (res.data as Map?)?['error'] ?? 'Could not delete account',
      );
    }
  }
}

/// Turns database/storage errors into short messages for people.
String friendlyError(Object e) {
  if (e is StateError) return e.message;
  final text = e is PostgrestException
      ? e.message
      : e is StorageException
      ? e.message
      : e is AuthException
      ? e.message
      : e.toString();
  if (text.contains('3 channels waiting')) {
    return 'You already have 3 channels waiting for approval.';
  }
  if (text.contains('quota')) return 'Not enough storage space left.';
  if (text.contains('plan_requests_one_open')) {
    return 'You already have a plan request waiting.';
  }
  if (text.contains('row-level security') ||
      text.contains('Unauthorized') ||
      text.contains('403')) {
    return "You don't have access to this.";
  }
  if (text.contains('login required')) return 'Please log in first.';
  if (text.contains('payments are not available')) {
    return 'Payments are not available right now.';
  }
  if (text.contains('Email not confirmed')) {
    return 'Please confirm your email first: open the link we sent you.';
  }
  if (text.contains('rate limit')) {
    return 'Too many emails were sent. Please try again in an hour.';
  }
  if (text.contains('Invalid login credentials')) {
    return 'Wrong email or password.';
  }
  if (text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('ClientException')) {
    return 'No internet connection.';
  }
  return text;
}
