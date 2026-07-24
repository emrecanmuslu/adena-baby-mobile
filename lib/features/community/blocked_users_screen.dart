import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/community_repository.dart';
import '../content/content_ui.dart' show parseHexColor;

/// Toplulukta engellenen kullanıcılar — görüntüle + engeli kaldır.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<Map<String, dynamic>>? _users;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(communityRepositoryProvider).blockedUsers();
      if (mounted) setState(() => _users = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _unblock(String id) async {
    try {
      await ref.read(communityRepositoryProvider).unblockUser(id);
      if (mounted) {
        setState(() => _users!.removeWhere((u) => u['id'] == id));
        showAdToast(context, tr('Engel kaldırıldı'));
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Engellenen kullanıcılar')),
      ),
      body: _error != null
          ? Center(
              child: Text(apiErrorText(_error!),
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)))
          : _users == null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    Skeleton(height: 64, radius: 14),
                    SizedBox(height: 10),
                    Skeleton(height: 64, radius: 14),
                  ],
                )
              : _users!.isEmpty
                  ? Center(
                      child: Text(tr('Engellediğin kimse yok.'),
                          style: TextStyle(
                              color: AppColors.muted, fontWeight: FontWeight.w600)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final u = _users![i];
                        final color = parseHexColor(u['color'] as String?) ?? AppColors.coral;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: AppColors.smallShadow,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(radius: 18, backgroundColor: color,
                                  child: Text(
                                      ((u['name'] as String).isNotEmpty
                                              ? (u['name'] as String)[0]
                                              : '?')
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w900))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(u['name'] as String,
                                      style: const TextStyle(fontWeight: FontWeight.w800))),
                              TextButton(
                                onPressed: () => _unblock(u['id'] as String),
                                child: Text(tr('Engeli kaldır')),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
