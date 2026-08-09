import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../widgets/omni_bar.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/tab_strip.dart';
import 'ntp_screen.dart';
import 'settings_screen.dart';
import 'side_panel_screen.dart';
import 'radar_screen.dart';
import 'downloads_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final BrowserController controller = BrowserController();
  final ScrollController tabScroll = ScrollController();
  final GlobalKey _webAreaKey = GlobalKey();
  final TextEditingController findCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.restore();
    });
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChange);
    controller.dispose();
    tabScroll.dispose();
    findCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final tab = controller.activeTab;
    final ctrl = controller.activeController;
    final isNew = tab?.isNewTab ?? true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (controller.findVisible) {
          controller.toggleFind();
          return;
        }
        if (controller.radarVisible) {
          controller.toggleRadar();
          return;
        }
        if (controller.sidePanelVisible) {
          controller.toggleSidePanel();
          return;
        }
        if (controller.downloadsVisible) {
          controller.toggleDownloads();
          return;
        }
        if (controller.settingsVisible) {
          controller.toggleSettings();
          return;
        }
        if (ctrl != null) {
          try {
            if (await ctrl.canGoBack()) {
              await controller.goBack();
              return;
            }
          } catch (_) {}
        }
        _handleClose(context);
      },
      child: Scaffold(
        backgroundColor: scheme.background,
        body: SafeArea(
          child: Column(
            children: [
              if (!isNew && ctrl != null && (tab?.loading ?? false))
                _ProgressBar(progress: tab?.progress ?? 0),
              OmniBar(controller: controller),
              if (!isNew)
                TabStrip(controller: controller, scroll: tabScroll),
              Expanded(
                key: _webAreaKey,
                child: Stack(
                  children: [
                    if (isNew || ctrl == null)
                      NewTabPage(controller: controller)
                    else
                      _buildWebView(ctrl),
                    if (controller.findVisible) _buildFindBar(),
                    if (controller.settingsVisible)
                      SettingsScreen(controller: controller),
                    if (controller.radarVisible)
                      RadarScreen(controller: controller),
                    if (controller.downloadsVisible)
                      DownloadsScreen(controller: controller),
                    if (controller.sidePanelVisible)
                      SidePanelScreen(controller: controller),
                  ],
                ),
              ),
              BottomToolbar(controller: controller),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView(WebViewController ctrl) {
    return WebViewWidget(controller: ctrl);
  }

  Widget _buildFindBar() {
    final scheme = AppTheme.scheme();
    return Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: findCtrl,
                  autofocus: true,
                  onChanged: (v) => controller.findNext(v),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: "Find in page",
                  ),
                  textInputAction: TextInputAction.search,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: () => controller.findNext(findCtrl.text),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: () => controller.findNext(findCtrl.text),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: controller.toggleFind,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleClose(BuildContext context) async {
    final s = SettingsService.instance.settings;
    if (s.confirmClose == 'on' && controller.tabCount > 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.scheme().surface,
          title: const Text("Close window?"),
          content: const Text(
              "You have open tabs. Closing the browser will lose them."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Close"),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    // Clear tabs and exit
    await controller.saveSession();
    await controller.closeAllTabs();
    if (mounted) {
      SystemNavigator.pop();
    }
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: scheme.primary,
    );
  }
}
