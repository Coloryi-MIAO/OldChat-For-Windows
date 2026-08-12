import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PublicCourtPage extends StatefulWidget {
  const PublicCourtPage({super.key});

  @override
  State<PublicCourtPage> createState() => _PublicCourtPageState();
}

class _PublicCourtPageState extends State<PublicCourtPage> {
  final _api = ApiService();
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _text(Map<String, dynamic> value, List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final item = value[key];
      if (item != null && item.toString().trim().isNotEmpty) return item.toString();
    }
    return fallback;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getPublicCourtCases(limit: 50);
      final raw = data['cases'] ?? data['items'] ?? data['list'] ?? data['data'] ?? data;
      if (!mounted) return;
      setState(() {
        _cases = _list(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openCase(Map<String, dynamic> item) async {
    final id = _text(item, const ['id', 'case_id']);
    if (id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PublicCourtCasePage(caseId: id, summary: item)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('公开法庭'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('加载失败：$_error'), TextButton(onPressed: _load, child: const Text('重试'))]))
              : _cases.isEmpty
                  ? const Center(child: Text('暂无公开案件'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _cases.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final item = _cases[index];
                        final title = _text(item, const ['title', 'subject', 'name'], '未命名案件');
                        final summary = _text(item, const ['summary', 'description', 'content', 'body']);
                        final status = _text(item, const ['status', 'state']);
                        return Card(
                          child: ListTile(
                            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (summary.isNotEmpty) Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                              if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('状态：$status', style: TextStyle(color: primary))),
                            ]),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openCase(item),
                          ),
                        );
                      },
                    ),
    );
  }
}

class PublicCourtCasePage extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> summary;
  const PublicCourtCasePage({super.key, required this.caseId, this.summary = const {}});

  @override
  State<PublicCourtCasePage> createState() => _PublicCourtCasePageState();
}

class _PublicCourtCasePageState extends State<PublicCourtCasePage> {
  final _api = ApiService();
  final _statementController = TextEditingController();
  Map<String, dynamic> _case = {};
  List<Map<String, dynamic>> _discussions = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _case = Map<String, dynamic>.from(widget.summary);
    _load();
  }

  @override
  void dispose() {
    _statementController.dispose();
    super.dispose();
  }

  String _text(Map<String, dynamic> value, List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final item = value[key];
      if (item != null && item.toString().trim().isNotEmpty) return item.toString();
    }
    return fallback;
  }

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return [];
    return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.getPublicCourtCase(widget.caseId),
        _api.getPublicCourtDiscussions(widget.caseId),
      ]);
      final caseData = results[0];
      final discussionData = results[1];
      final raw = discussionData['discussions'] ?? discussionData['items'] ?? discussionData['data'] ?? discussionData;
      if (!mounted) return;
      setState(() {
        _case = {..._case, ...caseData, if (caseData['data'] is Map) ...Map<String, dynamic>.from(caseData['data'])};
        _discussions = _list(raw);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Future<void> _vote(String vote) async {
    try {
      await _api.votePublicCourtCase(widget.caseId, vote);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('投票成功'))); _load(); }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('投票失败：$error')));
    }
  }

  Future<void> _sendStatement() async {
    final text = _statementController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.submitPublicCourtStatement(widget.caseId, text);
      _statementController.clear();
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('陈述已提交'))); _load(); }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败：$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final title = _text(_case, const ['title', 'subject', 'name'], '公开案件');
    final content = _text(_case, const ['content', 'description', 'summary', 'body']);
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: primary, foregroundColor: Colors.white),
      body: _loading && _case.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _case.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('加载失败：$_error'), TextButton(onPressed: _load, child: const Text('重试'))]))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (content.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(content, style: const TextStyle(fontSize: 15, height: 1.5)))),
                    Row(children: [
                      Expanded(child: FilledButton.icon(onPressed: () => _vote('support'), icon: const Icon(Icons.thumb_up_alt_outlined), label: const Text('支持'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: () => _vote('oppose'), icon: const Icon(Icons.thumb_down_alt_outlined), label: const Text('反对'))),
                    ]),
                    const SizedBox(height: 16),
                    const Text('提交陈述', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(controller: _statementController, minLines: 3, maxLines: 6, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '写下你的观点')),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _sending ? null : _sendStatement, child: Text(_sending ? '提交中…' : '提交'))),
                    const SizedBox(height: 16),
                    Text('讨论 (${_discussions.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (_discussions.isEmpty) const Text('暂无讨论', style: TextStyle(color: Colors.grey)),
                    ..._discussions.map((item) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(title: Text(_text(item, const ['display_name', 'username', 'uid'], '用户')), subtitle: Text(_text(item, const ['content', 'text', 'body'], ''))))),
                  ],
                ),
    );
  }
}
