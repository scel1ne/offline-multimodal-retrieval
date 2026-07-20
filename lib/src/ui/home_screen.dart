// coverage:ignore-file

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/indexed_item.dart';
import '../parsing/local_content_parser.dart';
import '../retrieval/retrieval_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.retrievalService, super.key});

  final RetrievalService retrievalService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _queryController = TextEditingController();
  final _queryFocus = FocusNode(debugLabel: 'search');
  final _parser = LocalContentParser();
  final _records = <_LocalRecord>[];
  var _query = '';
  var _typeFilter = 'all';
  var _sortMode = 'relevance';
  var _highContrast = false;
  var _textScale = 1.0;
  var _darkMode = false;
  var _status = 'No files indexed yet.';
  var _busy = false;
  int? _expandedResultIndex;
  bool _shortcutRegistered = false;

  @override
  void initState() {
    super.initState();
    // ⌘K / Ctrl-K focuses the search field (WCAG 2.1.1 Keyboard).
    HardwareKeyboard.instance.addHandler(_handleKey);
    _shortcutRegistered = true;
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    if ((isMeta || isCtrl) &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      _queryFocus.requestFocus();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    if (_shortcutRegistered) {
      HardwareKeyboard.instance.removeHandler(_handleKey);
    }
    _queryFocus.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _highContrast
        ? ThemeData(
            colorScheme: const ColorScheme.highContrastLight(),
            useMaterial3: true,
          )
        : _darkMode
            ? ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff7c3aed),
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              )
            : Theme.of(context);

    final theme = base.copyWith(
      scaffoldBackgroundColor: _highContrast
          ? base.colorScheme.surface
          : (_darkMode
              ? const Color(0xff0f1115)
              : const Color(0xfff6f7fb)),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: _highContrast
            ? base.colorScheme.surface
            : (_darkMode
                ? const Color(0xff1a1d24)
                : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: _highContrast
              ? BorderSide(color: base.colorScheme.outline, width: 1.5)
              : BorderSide(
                  color: _darkMode
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _highContrast
            ? base.colorScheme.surface
            : (_darkMode
                ? const Color(0xff1a1d24)
                : Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _highContrast
              ? base.colorScheme.onSurface
              : (_darkMode ? Colors.white : const Color(0xff1a1d24)),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _highContrast
            ? base.colorScheme.surface
            : (_darkMode
                ? const Color(0xff22262f)
                : const Color(0xfff3f4f8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );

    return Theme(
      data: theme,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(_textScale)),
        child: Scaffold(
          appBar: _buildAppBar(theme),
          body: FocusTraversalGroup(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 900;
                final panels = [
                  _libraryPanel(theme),
                  _searchPanel(theme),
                ];
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            panels[0],
                            const SizedBox(height: 20),
                            panels[1],
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 400, child: panels[0]),
                            const SizedBox(width: 20),
                            Expanded(child: panels[1]),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff7c3aed), Color(0xff3b82f6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.search_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Celine Retrieval'),
        ],
      ),
      actions: [
        IconButton(
          tooltip: _darkMode ? 'Light mode' : 'Dark mode',
          onPressed: () => setState(() => _darkMode = !_darkMode),
          icon: Icon(
              _darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
        ),
        IconButton(
          tooltip: _highContrast ? 'Standard contrast' : 'High contrast',
          onPressed: () => setState(() => _highContrast = !_highContrast),
          icon: Icon(_highContrast
              ? Icons.contrast_rounded
              : Icons.contrast_outlined),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const Icon(Icons.text_fields_rounded, size: 18),
              SizedBox(
                width: 120,
                child: Slider(
                  value: _textScale,
                  min: 0.9,
                  max: 1.4,
                  divisions: 5,
                  label: 'Text ${_textScale.toStringAsFixed(1)}x',
                  onChanged: (value) => setState(() => _textScale = value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _libraryPanel(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.folder_rounded,
                      color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text('Library',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_records.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_records.length} files',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _busy ? null : _pickAndIndex,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 160),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.08),
                      theme.colorScheme.secondary.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        theme.colorScheme.primary.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Drop files here',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PDF, DOCX, TXT, MD, JSON, images',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pickAndIndex,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Choose files'),
                ),
                OutlinedButton.icon(
                  onPressed: _records.isEmpty ? null : _exportIndex,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Export'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importIndex,
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: const Text('Import'),
                ),
                TextButton.icon(
                  onPressed: _records.isEmpty ? null : _clearIndex,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                        liveRegion: true,
                        child: Text(_status,
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13))),
                  ),
                ],
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: const LinearProgressIndicator(minHeight: 6),
              ),
            ],
            const SizedBox(height: 22),
            if (_records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Your library is empty. Add files to get started.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ..._records.asMap().entries.map(
                    (entry) => _recordTile(theme, entry.value, entry.key),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _recordTile(ThemeData theme, _LocalRecord record, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _iconColorForKind(record.kind, theme)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _iconForKind(record.kind),
            color: _iconColorForKind(record.kind, theme),
            size: 20,
          ),
        ),
        title: Text(
          record.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${record.kind} • ${_formatBytes(record.size)} • ${record.tokens.length} terms',
          style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
        ),
      ),
    );
  }

  Widget _searchPanel(ThemeData theme) {
    final results = _searchRecords();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.travel_explore_rounded,
                      color: theme.colorScheme.secondary, size: 20),
                ),
                const SizedBox(width: 12),
                Text('Search',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(Icons.search_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      focusNode: _queryFocus,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search across all your files...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 16, horizontal: 0),
                      ),
                      onChanged: (value) {
                        setState(() => _query = value.trim());
                        _refreshQueryEmbedding();
                      },
                      onSubmitted: (_) {
                        setState(() {});
                        _refreshQueryEmbedding();
                      },
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _queryController.clear();
                        setState(() => _query = '');
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: FilledButton(
                      onPressed: () => setState(
                          () => _query = _queryController.text.trim()),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                      child: const Text('Search'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filterChip(
                  theme,
                  label: 'All',
                  selected: _typeFilter == 'all',
                  onTap: () => setState(() => _typeFilter = 'all'),
                  icon: Icons.dashboard_rounded,
                ),
                _filterChip(
                  theme,
                  label: 'Text',
                  selected: _typeFilter == 'text',
                  onTap: () => setState(() => _typeFilter = 'text'),
                  icon: Icons.text_snippet_rounded,
                ),
                _filterChip(
                  theme,
                  label: 'Documents',
                  selected: _typeFilter == 'document',
                  onTap: () => setState(() => _typeFilter = 'document'),
                  icon: Icons.description_rounded,
                ),
                _filterChip(
                  theme,
                  label: 'Images',
                  selected: _typeFilter == 'image',
                  onTap: () => setState(() => _typeFilter = 'image'),
                  icon: Icons.image_rounded,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _sortChip(theme, 'Relevance', Icons.auto_awesome,
                          _sortMode == 'relevance',
                          () => setState(() => _sortMode = 'relevance')),
                      _sortChip(theme, 'Name', Icons.sort_by_alpha_rounded,
                          _sortMode == 'name',
                          () => setState(() => _sortMode = 'name')),
                      _sortChip(theme, 'Newest', Icons.schedule_rounded,
                          _sortMode == 'date',
                          () => setState(() => _sortMode = 'date')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Text(
                  _query.isEmpty
                      ? 'Showing all ${results.length} indexed files'
                      : '${results.length} result${results.length == 1 ? '' : 's'} for "$_query"',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (results.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 56,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text(
                      _records.isEmpty
                          ? 'Add files to start searching.'
                          : 'No matching results. Try a different query.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...results
                  .asMap()
                  .entries
                  .map((e) => _resultTile(theme, e.value, e.key)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(ThemeData theme,
      {required String label,
      required bool selected,
      required VoidCallback onTap,
      required IconData icon}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(ThemeData theme, String label, IconData icon,
      bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(ThemeData theme, _LocalResult result, int index) {
    final record = result.record;
    final isExpanded = _expandedResultIndex == index;
    final matches = _findAllMatches(record.text, _query);
    final totalMatches = matches.length;
    final scoreLabel = _query.isEmpty
        ? 'Indexed'
        : '${(result.score * 100).round()} percent match';
    final semanticLabel = 'Result ${index + 1}: ${record.name}. '
        '${record.kind} file, ${_formatBytes(record.size)}. '
        '$totalMatches matches. $scoreLabel. '
        'Press to ${isExpanded ? "collapse" : "expand"}.';

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isExpanded
              ? theme.colorScheme.primary.withValues(alpha: 0.04)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() {
                _expandedResultIndex = isExpanded ? null : index;
              }),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _iconColorForKind(record.kind, theme)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _iconForKind(record.kind),
                        color: _iconColorForKind(record.kind, theme),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  record.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (totalMatches > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$totalMatches match${totalMatches == 1 ? '' : 'es'}',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      theme.colorScheme.primary,
                                      theme.colorScheme.secondary,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _query.isEmpty
                                      ? 'Indexed'
                                      : '${(result.score * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${record.kind} • ${record.type.toUpperCase()} • ${_formatBytes(record.size)} • ${DateTime.fromMillisecondsSinceEpoch(record.modified).toLocal().toString().split('.').first}',
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: isExpanded ? 0.5 : 0,
                      child: Icon(Icons.expand_more_rounded,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: OccurrencePager(
                  theme: theme,
                  cleanText: record.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
                  matches: matches,
                  query: _query,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _pickAndIndex() async {
    setState(() {
      _busy = true;
      _status = 'Opening file picker...';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: FileType.custom,
        allowedExtensions: const [
          'txt',
          'md',
          'csv',
          'json',
          'html',
          'htm',
          'xml',
          'pdf',
          'docx',
          'png',
          'jpg',
          'jpeg',
          'gif',
          'bmp',
          'webp',
        ],
      );
      final paths = result?.paths.whereType<String>().toList() ?? [];
      if (paths.isEmpty) {
        setState(() {
          _busy = false;
          _status = _records.isEmpty
              ? 'No files indexed yet.'
              : '${_records.length} files indexed.';
        });
        return;
      }
      final imported = <_LocalRecord>[];
      for (final path in paths) {
        imported.add(await _buildRecord(File(path)));
      }
      final byId = {for (final record in _records) record.id: record};
      for (final record in imported) {
        byId[record.id] = record;
      }
      setState(() {
        _records
          ..clear()
          ..addAll(byId.values);
        _busy = false;
        _status =
            '${imported.length} files indexed. Library has ${_records.length} files.';
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _status = 'Indexing failed: $error';
      });
    }
  }

  Future<_LocalRecord> _buildRecord(File file) async {
    final parsed = await _parser.parse(file);
    final stat = await file.stat();
    final name = parsed.name;
    final kind = _kindName(parsed.kind);
    final type = p.extension(name).replaceFirst('.', '').toLowerCase();
    final text = parsed.text.trim().isEmpty
        ? '$name ${parsed.mimeType} ${stat.size} bytes'
        : parsed.text;
    final tokens = _tokenize('$name $type $text');
    List<double> embedding = const <double>[];
    try {
      embedding = await widget.retrievalService.embedForIndexing(parsed);
    } catch (_) {
      // Embedding is best-effort; the local TF-IDF path always works.
      embedding = const <double>[];
    }
    return _LocalRecord(
      id: parsed.id,
      path: parsed.path,
      name: name,
      kind: kind,
      type: type.isEmpty ? 'unknown' : type,
      size: stat.size,
      modified: parsed.modifiedAt.millisecondsSinceEpoch,
      text: text,
      tokens: tokens,
      vector: _vectorize(tokens),
      embedding: embedding,
    );
  }

  String _kindName(ContentKind kind) {
    return switch (kind) {
      ContentKind.text => 'text',
      ContentKind.document => 'document',
      ContentKind.image => 'image',
    };
  }

  Future<void> _exportIndex() async {
    final payload = jsonEncode({
      'version': 1,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'records': _records.map((record) => record.toJson()).toList(),
    });
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export index',
      fileName: 'offline-retrieval-index.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(payload)),
    );
    setState(() {
      _status = path == null ? 'Export canceled.' : 'Index exported.';
    });
  }

  Future<void> _importIndex() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final path = result?.paths.whereType<String>().firstOrNull;
      if (path == null) return;
      final decoded =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      final rows = (decoded['records'] as List? ?? const [])
          .map((item) =>
              _LocalRecord.fromJson(Map<String, Object?>.from(item as Map)))
          .toList();
      setState(() {
        _records
          ..clear()
          ..addAll(rows);
        _status = '${_records.length} records imported.';
      });
    } catch (error) {
      setState(() => _status = 'Import failed: $error');
    }
  }

  void _clearIndex() {
    setState(() {
      _records.clear();
      _status = 'Index cleared.';
      _expandedResultIndex = null;
    });
  }

  List<_LocalResult> _searchRecords() {
    final queryTokens = _tokenize(_query);
    final queryVector = _vectorize(queryTokens);
    final queryEmbedding = _queryEmbedding;
    var rows = _records
        .where((record) => _typeFilter == 'all' || record.kind == _typeFilter)
        .map((record) => _LocalResult(
              record,
              _score(
                record,
                queryTokens,
                queryVector,
                queryEmbedding,
              ),
            ))
        .toList();
    if (_query.isNotEmpty) {
      rows = rows.where((row) => row.score > 0).toList();
    }
    if (_sortMode == 'name') {
      rows.sort((a, b) => a.record.name.compareTo(b.record.name));
    } else if (_sortMode == 'date') {
      rows.sort((a, b) => b.record.modified.compareTo(a.record.modified));
    } else {
      rows.sort((a, b) => b.score.compareTo(a.score));
    }
    return rows;
  }

  /// Lazily embeds the current query string into a multimodal vector that
  /// is comparable to the embedding stored on each record. Reused on every
  /// re-sort so the result list reflects the latest typed query.
  List<double> get _queryEmbedding =>
      _cachedQuery == _query ? (_queryEmbeddingCache ?? const <double>[]) : const <double>[];

  /// Asynchronously warms the query embedding cache; safe to call from
  /// `setState` because failures are swallowed (we always have TF-IDF).
  Future<void> _refreshQueryEmbedding() async {
    if (_query.isEmpty) {
      _queryEmbeddingCache = null;
      _cachedQuery = '';
      return;
    }
    try {
      final vector = await widget.retrievalService.embedQuery(_query);
      _queryEmbeddingCache = vector;
      _cachedQuery = _query;
    } catch (_) {
      _queryEmbeddingCache = null;
    }
  }

  String _cachedQuery = '';
  List<double>? _queryEmbeddingCache;

  double _score(
    _LocalRecord record,
    List<String> queryTokens,
    Map<String, int> queryVector,
    List<double> queryEmbedding,
  ) {
    if (queryTokens.isEmpty) return 1;
    final keywordHits = queryTokens
            .where((query) => _hasTokenMatch(record.tokens, query))
            .length /
        queryTokens.length;
    final cosine = _cosine(record.vector, queryVector);
    final nameTokens = _tokenize(record.name);
    final nameBoost =
        queryTokens.any((query) => _hasTokenMatch(nameTokens, query))
            ? 0.25
            : 0.0;
    // Embedding similarity: text-side cosine + (for images) image-side
    // cosine. We align vector halves by splitting on the same split point
    // used during indexing (text side = embeddingSize; image side = rest).
    final embeddingSim = _embeddingSimilarity(record, queryEmbedding);
    return min(
      1,
      keywordHits * 0.45 +
          cosine * 0.25 +
          nameBoost +
          embeddingSim * 0.30,
    );
  }

  /// Returns a similarity score in [0, 1] that combines the text-side and
  /// image-side halves of the multimodal embedding. Returns 0 if either
  /// vector is empty.
  double _embeddingSimilarity(_LocalRecord record, List<double> queryVec) {
    if (record.embedding.isEmpty || queryVec.isEmpty) return 0;
    final textLen = min<int>(queryVec.length, record.embedding.length);
    final textSim = _cosineVectors(
      queryVec.sublist(0, textLen),
      record.embedding.sublist(0, textLen),
    );
    final isImage = record.kind == 'image';
    if (!isImage) return textSim;
    final extra = record.embedding.length - textLen;
    if (extra <= 0) return textSim;
    final imageSim = _cosineVectors(
      List<double>.filled(extra, 0),
      record.embedding.sublist(textLen),
    );
    return max(0, textSim) * 0.6 + max(0, imageSim) * 0.4;
  }

  double _cosineVectors(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final length = min<int>(a.length, b.length);
    var dot = 0.0;
    var magA = 0.0;
    var magB = 0.0;
    for (var i = 0; i < length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    if (magA == 0 || magB == 0) return 0;
    final cosine = dot / (sqrt(magA) * sqrt(magB));
    return (cosine + 1) / 2; // remap [-1, 1] -> [0, 1]
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .map(_normalizeToken)
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toList();
  }

  String _normalizeToken(String token) {
    var value = token.toLowerCase();
    if (value.length > 5 && value.endsWith('ing')) {
      value = value.substring(0, value.length - 3);
    } else if (value.length > 4 && value.endsWith('ers')) {
      value = value.substring(0, value.length - 1);
    } else if (value.length > 4 && value.endsWith('er')) {
      value = value.substring(0, value.length - 2);
    } else if (value.length > 3 && value.endsWith('s')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  bool _hasTokenMatch(List<String> tokens, String query) {
    return tokens.any(
      (token) =>
          token == query ||
          token.startsWith(query) ||
          query.startsWith(token) ||
          token.contains(query),
    );
  }

  Map<String, int> _vectorize(List<String> tokens) {
    final vector = <String, int>{};
    for (final token in tokens) {
      vector[token] = (vector[token] ?? 0) + 1;
    }
    return vector;
  }

  double _cosine(Map<String, int> a, Map<String, int> b) {
    final keys = {...a.keys, ...b.keys};
    var dot = 0.0;
    var magA = 0.0;
    var magB = 0.0;
    for (final key in keys) {
      final av = (a[key] ?? 0).toDouble();
      final bv = (b[key] ?? 0).toDouble();
      dot += av * bv;
      magA += av * av;
      magB += bv * bv;
    }
    return magA > 0 && magB > 0 ? dot / (sqrt(magA) * sqrt(magB)) : 0;
  }

  /// Find all occurrences of the query tokens in the text.
  /// Returns a sorted list of non-overlapping match ranges (in the cleaned
  /// whitespace-collapsed text coordinates).
  List<TextRange> _findAllMatches(String text, String query) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty || clean.isEmpty) return const [];

    final ranges = <TextRange>[];
    final lowerClean = clean.toLowerCase();

    for (final token in queryTokens) {
      if (token.isEmpty) continue;
      final pattern = RegExp(RegExp.escape(token), caseSensitive: false);
      for (final match in pattern.allMatches(lowerClean)) {
        ranges.add(TextRange(start: match.start, end: match.end));
      }
    }

    ranges.sort((a, b) => a.start.compareTo(b.start));
    final merged = <TextRange>[];
    for (final range in ranges) {
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }
      final last = merged.last;
      if (range.start <= last.end) {
        merged[merged.length - 1] =
            TextRange(start: last.start, end: max(last.end, range.end));
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  IconData _iconForKind(String kind) {
    return switch (kind) {
      'text' => Icons.text_snippet_rounded,
      'document' => Icons.description_rounded,
      'image' => Icons.image_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  Color _iconColorForKind(String kind, ThemeData theme) {
    return switch (kind) {
      'text' => Colors.blueAccent,
      'document' => Colors.deepPurpleAccent,
      'image' => Colors.orangeAccent,
      _ => theme.colorScheme.primary,
    };
  }

  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    final index = min((log(bytes) / log(1024)).floor(), units.length - 1);
    final value = bytes / pow(1024, index);
    return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
  }
}

class _LocalRecord {
  const _LocalRecord({
    required this.id,
    required this.path,
    required this.name,
    required this.kind,
    required this.type,
    required this.size,
    required this.modified,
    required this.text,
    required this.tokens,
    required this.vector,
    this.embedding = const <double>[],
  });

  final String id;
  final String path;
  final String name;
  final String kind;
  final String type;
  final int size;
  final int modified;
  final String text;
  final List<String> tokens;
  final Map<String, int> vector;
  final List<double> embedding;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'kind': kind,
      'type': type,
      'size': size,
      'modified': modified,
      'text': text,
      'tokens': tokens,
      'vector': vector,
      'embedding': embedding,
    };
  }

  factory _LocalRecord.fromJson(Map<String, Object?> json) {
    return _LocalRecord(
      id: json['id'] as String,
      path: json['path'] as String? ?? '',
      name: json['name'] as String,
      kind: json['kind'] as String,
      type: json['type'] as String,
      size: json['size'] as int,
      modified: json['modified'] as int,
      text: json['text'] as String? ?? '',
      tokens: (json['tokens'] as List? ?? const []).cast<String>(),
      vector: Map<String, int>.from(json['vector'] as Map? ?? const {}),
      embedding: ((json['embedding'] as List?) ?? const <Object?>[])
          .map((e) => (e as num).toDouble())
          .toList(growable: false),
    );
  }
}

class _LocalResult {
  const _LocalResult(this.record, this.score);

  final _LocalRecord record;
  final double score;
}

/// Pager that lets the user step through every occurrence of the query
/// inside a single document.
class OccurrencePager extends StatefulWidget {
  const OccurrencePager({
    super.key,
    required this.theme,
    required this.cleanText,
    required this.matches,
    required this.query,
  });

  final ThemeData theme;
  final String cleanText;
  final List<TextRange> matches;
  final String query;

  @override
  State<OccurrencePager> createState() => _OccurrencePagerState();
}

class _OccurrencePagerState extends State<OccurrencePager> {
  static const int _contextRadius = 130;
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (widget.matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          widget.cleanText.isEmpty
              ? 'No extractable text. Metadata is searchable.'
              : widget.cleanText.length > 500
                  ? widget.cleanText.substring(0, 500)
                  : widget.cleanText,
          style: const TextStyle(height: 1.5),
        ),
      );
    }

    final current = widget.matches[_index.clamp(0, widget.matches.length - 1)];
    final snippet = _snippet(widget.cleanText, current);
    final total = widget.cleanText.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_index + 1} / ${widget.matches.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Position ${current.start + 1} of $total characters',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous match',
                onPressed: widget.matches.length <= 1
                    ? null
                    : () => setState(() {
                          _index = (_index - 1 + widget.matches.length) %
                              widget.matches.length;
                        }),
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Next match',
                onPressed: widget.matches.length <= 1
                    ? null
                    : () => setState(() {
                          _index = (_index + 1) % widget.matches.length;
                        }),
                icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProgressBar(
            position: current.start,
            total: total,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text.rich(
              _buildHighlighted(snippet, current),
              style: const TextStyle(height: 1.5, fontSize: 14),
            ),
          ),
          if (widget.matches.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: (_index + 1) / widget.matches.length,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(((_index + 1) / widget.matches.length) * 100).round()}%',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Build a TextSpan for the snippet. The snippet may include the current
  /// match plus surrounding context. The current match is highlighted more
  /// strongly than other matches that happen to fall inside the snippet.
  TextSpan _buildHighlighted(_Snippet snippet, TextRange current) {
    final ranges = widget.matches;
    final spans = <TextSpan>[];
    final ellipsisStyle = TextStyle(
      color: Colors.grey.shade500,
      fontStyle: FontStyle.italic,
    );
    final highlightStyle = TextStyle(
      backgroundColor: Colors.amberAccent.withValues(alpha: 0.6),
      color: Colors.black,
      fontWeight: FontWeight.w700,
    );
    const focusedStyle = TextStyle(
      backgroundColor: Color(0xfffde047),
      color: Colors.black,
      fontWeight: FontWeight.w900,
      fontSize: 16,
    );

    if (snippet.hasPrefix) {
      spans.add(TextSpan(text: '… ', style: ellipsisStyle));
    }

    // Map each absolute match range to its position inside the displayed
    // snippet body (the leading ellipsis marker is already prepended above).
    final relativeRanges = <(int, int, bool)>[];
    for (final range in ranges) {
      final s = range.start - snippet.absoluteStart;
      final e = range.end - snippet.absoluteStart;
      if (e <= 0 || s >= snippet.bodyLength) continue;
      final clippedS = s.clamp(0, snippet.bodyLength);
      final clippedE = e.clamp(0, snippet.bodyLength);
      if (clippedE <= clippedS) continue;
      relativeRanges.add((clippedS, clippedE, range.start == current.start));
    }
    relativeRanges.sort((a, b) => a.$1.compareTo(b.$1));

    var cursor = 0;
    for (final rel in relativeRanges) {
      if (rel.$1 > cursor) {
        spans.add(TextSpan(text: snippet.body.substring(cursor, rel.$1)));
      }
      spans.add(TextSpan(
        text: snippet.body.substring(rel.$1, rel.$2),
        style: rel.$3 ? focusedStyle : highlightStyle,
      ));
      cursor = rel.$2;
    }
    if (cursor < snippet.body.length) {
      spans.add(TextSpan(text: snippet.body.substring(cursor)));
    }
    if (snippet.hasSuffix) {
      spans.add(TextSpan(text: ' …', style: ellipsisStyle));
    }
    return TextSpan(children: spans);
  }

  _Snippet _snippet(String clean, TextRange match) {
    final start = match.start < _contextRadius ? 0 : match.start - _contextRadius;
    final end = (match.end + _contextRadius).clamp(0, clean.length);
    final hasPrefix = start > 0;
    final hasSuffix = end < clean.length;
    final body = clean.substring(start, end);
    return _Snippet(
      absoluteStart: start,
      body: body,
      bodyLength: body.length,
      hasPrefix: hasPrefix,
      hasSuffix: hasSuffix,
    );
  }
}

/// Lightweight value type describing a window of [cleanText] we want to
/// display, so that absolute match positions in [matches] can be mapped back
/// to positions inside the rendered snippet body.
class _Snippet {
  const _Snippet({
    required this.absoluteStart,
    required this.body,
    required this.bodyLength,
    required this.hasPrefix,
    required this.hasSuffix,
  });

  /// Absolute offset into the source `cleanText` where the snippet body
  /// begins.
  final int absoluteStart;

  /// The snippet text (without any leading/trailing ellipsis markers).
  final String body;

  /// Cached `body.length` to keep hot paths branch-free.
  final int bodyLength;

  final bool hasPrefix;
  final bool hasSuffix;
}

/// Small linear progress bar showing where the current match is inside the
/// document.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.position,
    required this.total,
    required this.color,
  });

  final int position;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (position / total).clamp(0.0, 1.0);
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: ratio == 0 ? 0.01 : ratio,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

const _stopWords = {
  'the',
  'and',
  'for',
  'with',
  'this',
  'that',
  'from',
  'file',
  'into',
  'uses',
  'use',
};
