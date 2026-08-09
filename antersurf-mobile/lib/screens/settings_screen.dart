import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../services/anterget_service.dart';
import '../services/app_database.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final BrowserController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _page = 0;

  void _close() {
    widget.controller.toggleSettings();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return Positioned.fill(
      child: Material(
        color: scheme.background,
        child: Column(
          children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (_page == 0) {
                      _close();
                    } else {
                      setState(() => _page = 0);
                    }
                  },
                ),
                const Text("Settings",
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _close,
                ),
              ],
            ),
          ),
            Expanded(
              child: _page == 0 ? _buildNav() : _buildDetail(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNav() {
    final s = SettingsService.instance.settings;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _GroupHeader("General"),
        _NavTile(Icons.language, "Search engine",
            _label(s.searchEngine), () => setState(() => _page = 1)),
        _NavTile(Icons.palette_outlined, "Appearance",
            "${_label(s.theme)} · ${s.accent}", () => setState(() => _page = 2)),
        _NavTile(Icons.home_outlined, "Startup",
            s.startup == 'last' ? "Restore last session" : s.homepage,
            () => setState(() => _page = 3)),
        _GroupHeader("Privacy"),
        _NavTile(Icons.shield_outlined, "Tracking protection",
            _label(s.tracking), () => setState(() => _page = 4)),
        _SwitchTile("Do Not Track", s.dnt == 'on', (v) {
          SettingsService.instance.set('dnt', v ? 'on' : 'off');
        }),
        _SwitchTile("Block cookies", s.cookies == 'on', (v) {
          SettingsService.instance.set('cookies', v ? 'on' : 'off');
        }),
        _NavTile(Icons.location_on_outlined, "Location access",
            _label(s.location), () => setState(() => _page = 5)),
        _SwitchTile("Suggestions", s.suggest == 'on', (v) {
          SettingsService.instance.set('suggest', v ? 'on' : 'off');
        }),
        _GroupHeader("Interface"),
        _SwitchTile("Show home button", s.showHomeBtn, (v) {
          SettingsService.instance.set('showHomeBtn', v);
        }),
        _SwitchTile("Show copy button", s.showCopyBtn, (v) {
          SettingsService.instance.set('showCopyBtn', v);
        }),
        _SwitchTile("NTP clock", s.showNtpClock, (v) {
          SettingsService.instance.set('showNtpClock', v);
        }),
        _SwitchTile("NTP logo", s.showNtpLogo, (v) {
          SettingsService.instance.set('showNtpLogo', v);
        }),
        _SwitchTile("Confirm on close", s.confirmClose == 'on', (v) {
          SettingsService.instance.set('confirmClose', v ? 'on' : 'off');
        }),
        _SwitchTile("Reduce animations", s.reduceAnimations == 'on', (v) {
          SettingsService.instance.set('reduceAnimations', v ? 'on' : 'off');
        }),
        _SwitchTile("Progress bar", s.showProgressBar, (v) {
          SettingsService.instance.set('showProgressBar', v);
        }),
        _NavTile(Icons.text_fields, "Font size",
            "${s.fontSize}px", () => setState(() => _page = 6)),
        _NavTile(Icons.speed, "Speed dial",
            _label(s.speedDial), () => setState(() => _page = 7)),
        _GroupHeader("Downloads"),
        _NavTile(Icons.download_outlined, "Downloads",
            "AnterGet · ${s.downloadsParallel} parallel",
            () => setState(() => _page = 9)),
        _GroupHeader("Data"),
        _NavTile(Icons.history, "Clear browsing data", "",
            () => _confirmClearData()),
        _NavTile(Icons.info_outline, "About", "AnterSurf 27.0.0",
            () => setState(() => _page = 8)),
      ],
    );
  }

  Widget _buildDetail() {
    switch (_page) {
      case 1:
        return _buildSearchEngine();
      case 2:
        return _buildAppearance();
      case 3:
        return _buildStartup();
      case 4:
        return _buildTracking();
      case 5:
        return _buildLocation();
      case 6:
        return _buildFontSize();
      case 7:
        return _buildSpeedDial();
      case 8:
        return _buildAbout();
      case 9:
        return _buildDownloads();
      default:
        return const SizedBox();
    }
  }

  Widget _buildSearchEngine() {
    final s = SettingsService.instance.settings;
    const engines = [
      ('duckduckgo', 'DuckDuckGo', 'Default — private'),
      ('google', 'Google', ''),
      ('bing', 'Bing', ''),
      ('brave', 'Brave', ''),
      ('yahoo', 'Yahoo', ''),
      ('ecosia', 'Ecosia', ''),
      ('custom', 'Custom', ''),
    ];
    return _DetailPage(
      title: "Search engine",
      body: Column(
        children: [
          for (final (id, name, note) in engines)
            RadioListTile<String>(
              value: id,
              groupValue: s.searchEngine,
              onChanged: (v) {
                if (v != null) {
                  SettingsService.instance.set('searchEngine', v);
                }
              },
              title: Text(name),
              subtitle: note.isEmpty ? null : Text(note),
            ),
          if (s.searchEngine == 'custom')
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller:
                    TextEditingController(text: s.customEngine),
                onChanged: (v) =>
                    SettingsService.instance.set('customEngine', v),
                decoration: const InputDecoration(
                  labelText: "Custom engine URL",
                  hintText: "https://search.example.com/?q=",
                ),
              ),
            ),
        ],
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Widget _buildAppearance() {
    final s = SettingsService.instance.settings;
    const themes = [
      ('dark', 'Dark'),
      ('light', 'Light'),
      ('system', 'System'),
    ];
    const accents = [
      ('#8ab4f8', 'Blue'),
      ('#4fc3f7', 'Cyan'),
      ('#BCA0DD', 'Lavender'),
      ('#7fb069', 'Green'),
      ('#ff5f6d', 'Red'),
      ('#ffd166', 'Yellow'),
      ('#FC8EAC', 'Pink'),
    ];
    return _DetailPage(
      title: "Appearance",
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GroupHeader("Theme"),
          for (final (id, name) in themes)
            RadioListTile<String>(
              value: id,
              groupValue: s.theme,
              onChanged: (v) {
                if (v != null) {
                  SettingsService.instance.set('theme', v);
                }
              },
              title: Text(name),
            ),
          const _GroupHeader("Accent color"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (hex, name) in accents)
                  GestureDetector(
                    onTap: () =>
                        SettingsService.instance.set('accent', hex),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.accentFrom(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: s.accent == hex
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(name,
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const _GroupHeader("Corner radius"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'small', label: Text("Small")),
                ButtonSegment(value: 'medium', label: Text("Medium")),
                ButtonSegment(value: 'large', label: Text("Large")),
              ],
              selected: {s.uiRadius},
              onSelectionChanged: (v) {
                SettingsService.instance.set('uiRadius', v.first);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Widget _buildStartup() {
    final s = SettingsService.instance.settings;
    return _DetailPage(
      title: "Startup",
      body: Column(
        children: [
          RadioListTile<String>(
            value: 'last',
            groupValue: s.startup,
            onChanged: (v) {
              if (v != null) SettingsService.instance.set('startup', v);
            },
            title: const Text("Restore last session"),
            subtitle: const Text("Reopen tabs from previous run"),
          ),
          RadioListTile<String>(
            value: 'home',
            groupValue: s.startup,
            onChanged: (v) {
              if (v != null) SettingsService.instance.set('startup', v);
            },
            title: const Text("Open home page"),
          ),
          RadioListTile<String>(
            value: 'newtab',
            groupValue: s.startup,
            onChanged: (v) {
              if (v != null) SettingsService.instance.set('startup', v);
            },
            title: const Text("New tab page"),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: TextEditingController(text: s.homepage),
              onChanged: (v) =>
                  SettingsService.instance.set('homepage', v),
              decoration: const InputDecoration(
                labelText: "Home page",
                hintText: "https://",
              ),
            ),
          ),
        ],
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Widget _buildTracking() {
    final s = SettingsService.instance.settings;
    const levels = [
      ('standard', 'Standard', 'Block obvious trackers'),
      ('strict', 'Strict', 'Block more trackers, may break sites'),
      ('off', 'Off', 'No protection'),
    ];
    return _DetailPage(
      title: "Tracking protection",
      body: Column(
        children: [
          for (final (id, name, note) in levels)
            RadioListTile<String>(
              value: id,
              groupValue: s.tracking,
              onChanged: (v) {
                if (v != null) {
                  SettingsService.instance.set('tracking', v);
                }
              },
              title: Text(name),
              subtitle: Text(note),
            ),
          const Divider(),
          _SwitchTile("Do Not Track", s.dnt == 'on', (v) {
            SettingsService.instance.set('dnt', v ? 'on' : 'off');
          }),
          _SwitchTile("Block cookies", s.cookies == 'on', (v) {
            SettingsService.instance.set('cookies', v ? 'on' : 'off');
          }),
          _SwitchTile("Send referrer", s.sendReferrer, (v) {
            SettingsService.instance.set('sendReferrer', v);
          }),
        ],
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Widget _buildLocation() {
    final s = SettingsService.instance.settings;
    const modes = [
      ('block', 'Block', 'Always deny location'),
      ('ask', 'Ask', 'Ask before sharing'),
      ('allow', 'Allow', 'Always share location'),
    ];
    return _DetailPage(
      title: "Location access",
      body: Column(
        children: [
          for (final (id, name, note) in modes)
            RadioListTile<String>(
              value: id,
              groupValue: s.location,
              onChanged: (v) {
                if (v != null) {
                  SettingsService.instance.set('location', v);
                }
              },
              title: Text(name),
              subtitle: Text(note),
            ),
        ],
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Widget _buildFontSize() {
    final s = SettingsService.instance.settings;
    final current = double.tryParse(s.fontSize) ?? 12;
    return _DetailPage(
      title: "Font size",
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${current.round()}px",
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
            Slider(
              value: current,
              min: 10,
              max: 16,
              divisions: 6,
              label: "${current.round()}px",
              onChanged: (v) =>
                  SettingsService.instance.set('fontSize', '${v.round()}'),
            ),
          ],
        ),
      ),
    
      onBack: () => setState(() => _page = 0),
    );
  }

  Widget _buildSpeedDial() {
    final s = SettingsService.instance.settings;
    const modes = [
      ('comfortable', 'Comfortable', '4 columns'),
      ('compact', 'Compact', '5 columns'),
    ];
    return _DetailPage(
      title: "Speed dial",
      body: Column(
        children: [
          for (final (id, name, note) in modes)
            RadioListTile<String>(
              value: id,
              groupValue: s.speedDial,
              onChanged: (v) {
                if (v != null) {
                  SettingsService.instance.set('speedDial', v);
                }
              },
              title: Text(name),
              subtitle: Text(note),
            ),
        ],
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Widget _buildDownloads() {
    final s = SettingsService.instance.settings;
    final scheme = AppTheme.scheme();
    return _DetailPage(
      title: "Downloads",
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GroupHeader("Parallel downloads"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("At most ${s.downloadsParallel} at once"),
                    Text(
                      "1-4",
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: .5)),
                    ),
                  ],
                ),
                Slider(
                  value: s.downloadsParallel.toDouble().clamp(1, 4).toDouble(),
                  min: 1,
                  max: 4,
                  divisions: 3,
                  label: "${s.downloadsParallel}",
                  onChanged: (v) => SettingsService.instance
                      .set('downloadsParallel', v.round()),
                ),
              ],
            ),
          ),
          const Divider(),
          const _GroupHeader("Engine"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "AnterGet transfers every download with libcurl in a "
              "background isolate. Pauses resume from where they stopped "
              "using HTTP Range requests.",
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: scheme.onSurface.withValues(alpha: .75)),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text("Open downloads"),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              widget.controller.toggleSettings();
              widget.controller.toggleDownloads();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text("Clear all downloads"),
            onTap: () => _confirmClearDownloads(),
          ),
          const SizedBox(height: 24),
        ],
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Future<void> _confirmClearDownloads() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear all downloads?"),
        content: const Text(
            "Removes all downloads and deletes their files from storage."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Clear")),
        ],
      ),
    );
    if (ok == true) {
      await AnterGetService.instance.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Downloads cleared")),
        );
      }
    }
  }

  Widget _buildAbout() {
    return _DetailPage(
      title: "About",
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.scheme().surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.public,
                  size: 38, color: AppTheme.scheme().primary),
            ),
            const SizedBox(height: 16),
            const Text("AnterSurf",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const Text("Version 27.0.0"),
            const SizedBox(height: 12),
            const Text(
              "Privacy-first browser built by PlanetOfOSes, "
              "a sub-brand of Nexunfog Solutions.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      onBack: () => setState(() => _page = 0),
    );
  }

  Future<void> _confirmClearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear browsing data?"),
        content: const Text("This deletes history, bookmarks, downloads and top sites."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Clear")),
        ],
      ),
    );
    if (ok == true) {
      await AppDatabase.instance.clearHistory();
      await AppDatabase.instance.clearBookmarks();
      await AnterGetService.instance.clear();
      await AppDatabase.instance.clearTopSites();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Browsing data cleared")),
        );
      }
    }
  }

  String _label(String v) {
    switch (v) {
      case 'duckduckgo':
        return 'DuckDuckGo';
      case 'google':
        return 'Google';
      case 'bing':
        return 'Bing';
      case 'brave':
        return 'Brave';
      case 'yahoo':
        return 'Yahoo';
      case 'ecosia':
        return 'Ecosia';
      case 'custom':
        return 'Custom';
      case 'on':
        return 'On';
      case 'off':
        return 'Off';
      case 'standard':
        return 'Standard';
      case 'strict':
        return 'Strict';
      case 'dark':
        return 'Dark';
      case 'light':
        return 'Light';
      case 'system':
        return 'System';
      case 'block':
        return 'Block';
      case 'ask':
        return 'Ask';
      case 'allow':
        return 'Allow';
      case 'comfortable':
        return 'Comfortable';
      case 'compact':
        return 'Compact';
      default:
        return v.isEmpty ? "—" : v;
    }
  }
}

class _DetailPage extends StatelessWidget {
  final String title;
  final Widget body;
  final VoidCallback onBack;
  const _DetailPage({required this.title, required this.body, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [body]),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  const _GroupHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  const _NavTile(this.icon, this.title, this.value, this.onTap);

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return ListTile(
      leading: Icon(icon, size: 20, color: scheme.onSurface),
      title: Text(title),
      subtitle: value.isEmpty ? null : Text(value),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile(this.title, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}
