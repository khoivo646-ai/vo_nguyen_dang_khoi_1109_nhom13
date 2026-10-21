import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../utils/auth.dart';
import 'customer_screen.dart';
import 'face_auth_screen.dart';
import 'login_screen.dart';

/// Màn hình Quản trị viên (Role: Admin):
/// - Tab 1: Quản lý & Cấp tài khoản người dùng (Admin / Parent / Child), đổi quyền, mở khóa, xóa tài khoản.
/// - Tab 2: Quản lý toàn bộ thiết bị trẻ em trong hệ thống (CRUD + GPS + Tiếng ồn).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final AdminService _adminService = AdminService();
  final TextEditingController _searchUserCtrl = TextEditingController();

  List<UserAccountItem> _users = [];
  bool _loadingUsers = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchUserCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers({String? search}) async {
    setState(() => _loadingUsers = true);
    try {
      final list = await _adminService.getUsers(search: search);
      if (!mounted) return;
      setState(() => _users = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  void _openCreateUserDialog() {
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final initialsCtrl = TextEditingController(text: 'KG');
    String selectedRole = 'Parent';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Cấp Tài Khoản Mới (Admin)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên đăng nhập *',
                    prefixIcon: Icon(Icons.person_add_alt_1),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu khởi tạo (>= 6 ký tự) *',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: initialsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ký tự viết tắt',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Quyền hệ thống',
                    prefixIcon: Icon(Icons.security),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'Admin', child: Text('Admin - Quản trị viên')),
                    DropdownMenuItem(
                        value: 'Parent',
                        child: Text('Parent - Phụ huynh quản lý')),
                    DropdownMenuItem(
                        value: 'Child',
                        child: Text('Child - Tài khoản Trẻ em')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedRole = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange.shade700,
              ),
              onPressed: () async {
                if (usernameCtrl.text.trim().isEmpty ||
                    emailCtrl.text.trim().isEmpty ||
                    passwordCtrl.text.length < 6) {
                  return;
                }
                Navigator.pop(ctx);
                final res = await _adminService.createUser(
                  username: usernameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  password: passwordCtrl.text,
                  role: selectedRole,
                  initials: initialsCtrl.text.trim(),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? ''),
                    backgroundColor:
                        res['success'] == true ? Colors.green : Colors.red,
                  ),
                );
                _fetchUsers();
              },
              child: const Text(
                'Cấp Tài Khoản',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _roleBadgeColor(String role) {
    if (role == 'Admin') return Colors.deepOrange;
    if (role == 'Child') return Colors.teal;
    return Colors.indigo;
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade700,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Tổng tài khoản: ${_users.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.deepOrange.shade800,
                    ),
                    onPressed: _openCreateUserDialog,
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text(
                      'Cấp tài khoản',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchUserCtrl,
                onSubmitted: (v) => _fetchUsers(search: v),
                decoration: InputDecoration(
                  hintText: 'Tìm theo username hoặc email...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchUserCtrl.clear();
                      _fetchUsers();
                    },
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingUsers
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _users.length,
                  itemBuilder: (_, idx) {
                    final u = _users[idx];
                    final roleColor = _roleBadgeColor(u.primaryRole);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      roleColor.withValues(alpha: 0.15),
                                  child: Icon(Icons.person, color: roleColor),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.username,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        u.email,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownButton<String>(
                                  value: ['Admin', 'Parent', 'Child']
                                          .contains(u.primaryRole)
                                      ? u.primaryRole
                                      : 'Parent',
                                  underline: const SizedBox.shrink(),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'Admin', child: Text('Admin')),
                                    DropdownMenuItem(
                                        value: 'Parent', child: Text('Parent')),
                                    DropdownMenuItem(
                                        value: 'Child', child: Text('Child')),
                                  ],
                                  onChanged: (newRole) async {
                                    if (newRole == null ||
                                        newRole == u.primaryRole) {
                                      return;
                                    }
                                    final res = await _adminService.setUserRole(
                                      u.username,
                                      newRole,
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res['message'] ?? ''),
                                        backgroundColor: res['success'] == true
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    );
                                    _fetchUsers(search: _searchUserCtrl.text);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    u.emailConfirmed
                                        ? Icons.verified
                                        : Icons.mail_lock,
                                    size: 16,
                                    color: u.emailConfirmed
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  label: Text(
                                    u.emailConfirmed
                                        ? 'Đã xác minh Email'
                                        : 'Chưa xác minh Email',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                ),
                                if (u.hasFace)
                                  const Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: Icon(Icons.face_retouching_natural,
                                        size: 16, color: Colors.indigo),
                                    label: Text(
                                      'Đã đăng ký Face AI',
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                if (u.isLockedOut)
                                  ActionChip(
                                    backgroundColor: Colors.red.shade50,
                                    avatar: const Icon(Icons.lock_open,
                                        size: 16, color: Colors.red),
                                    label: const Text('Mở khóa TK'),
                                    onPressed: () async {
                                      await _adminService
                                          .unlockUser(u.username);
                                      _fetchUsers();
                                    },
                                  ),
                                IconButton(
                                  tooltip: 'Xóa tài khoản',
                                  onPressed: () async {
                                    final res = await _adminService
                                        .deleteUser(u.username);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res['message'] ?? ''),
                                        backgroundColor: res['success'] == true
                                            ? Colors.teal
                                            : Colors.red,
                                      ),
                                    );
                                    _fetchUsers();
                                  },
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: Colors.deepOrange.shade700,
        foregroundColor: Colors.white,
        title: const Text(
          'ADMIN - Quản Trị Hệ Thống KidGuard',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Đăng ký Khuôn mặt AI',
            icon: const Icon(Icons.face_retouching_natural),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const FaceAuthScreen(mode: FaceAuthMode.register),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final nav = Navigator.of(context);
              await Auth.logout();
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.supervisor_account), text: 'Cấp Tài Khoản & Role'),
            Tab(icon: Icon(Icons.devices_other), text: 'Tất Cả Thiết Bị'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(),
          CustomerScreen(
            dashboardTitle: 'Quản Trị Tất Cả Thiết Bị',
            roleBadge: 'QUẢN TRỊ VIÊN (ADMIN)',
            primaryColor: Colors.deepOrange.shade700,
            isAdminView: true,
          ),
        ],
      ),
    );
  }
}
