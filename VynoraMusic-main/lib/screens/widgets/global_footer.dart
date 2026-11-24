import 'dart:io' as io;
import 'dart:ui' show ImageFilter;
import 'package:streambeats/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:streambeats/screens/widgets/player_overlay_wrapper.dart';
import 'package:streambeats/screens/widgets/mini_player_widget.dart';
import 'package:streambeats/core/theme/app_theme.dart';
import 'package:streambeats/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'package:streambeats/screens/widgets/home_sidebar_drawer.dart';

class GlobalFooter extends StatelessWidget {
  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  const GlobalFooter({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    context.watch<PlayerOverlayCubit>();
    final isMobile = io.Platform.isAndroid ||
        io.Platform.isIOS ||
        ResponsiveBreakpoints.of(context).smallerOrEqualTo(TABLET);

    return PlayerOverlayWrapper(
      child: BackButtonListener(
        onBackButtonPressed: () async {
          final overlayC = context.read<PlayerOverlayCubit>();
          final router = GoRouter.of(context);

          if (router.canPop()) {
            router.pop();
            return true;
          }

          if (overlayC.state && overlayC.collapseUpNextPanel()) {
            return true;
          }

          if (overlayC.state) {
            overlayC.hidePlayer();
            return true;
          }

          return false;
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            await _handleHardwareBackPress(context);
          },
          child: Scaffold(
            key: scaffoldKey,
            backgroundColor: Default_Theme.themeColor,
            drawerScrimColor: Colors.black.withValues(alpha: 0.5),
            drawer: HomeSidebarDrawer(navigationShell: navigationShell),
            body: isMobile
                ? _AnimatedPageView(navigationShell: navigationShell)
                : Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: VerticalNavBar(navigationShell: navigationShell),
                      ),
                      Expanded(
                        child:
                            _AnimatedPageView(navigationShell: navigationShell),
                      ),
                    ],
                  ),
            bottomNavigationBar: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayerWidget(),
                  if (isMobile)
                    Container(
                      color: Colors.transparent,
                      margin: const EdgeInsets.symmetric(
                          vertical: 5, horizontal: 10),
                      child: HorizontalNavBar(navigationShell: navigationShell),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleHardwareBackPress(BuildContext context) async {
    final overlayC = context.read<PlayerOverlayCubit>();
    final router = GoRouter.of(context);

    if (router.canPop()) {
      router.pop();
      return;
    }

    if (overlayC.state && overlayC.collapseUpNextPanel()) return;

    if (overlayC.state) {
      overlayC.hidePlayer();
      return;
    }

    if (navigationShell.currentIndex != 0) {
      navigationShell.goBranch(0);
      return;
    }

    if (context.mounted) {
      await SystemNavigator.pop();
    }
  }
}

class _AnimatedPageView extends StatefulWidget {
  const _AnimatedPageView({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  State<_AnimatedPageView> createState() => _AnimatedPageViewState();
}

class _AnimatedPageViewState extends State<_AnimatedPageView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.navigationShell.currentIndex;

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void didUpdateWidget(_AnimatedPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell.currentIndex != _previousIndex) {
      _previousIndex = widget.navigationShell.currentIndex;
      _animationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.navigationShell,
      ),
    );
  }
}

class VerticalNavBar extends StatelessWidget {
  const VerticalNavBar({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return NavigationRail(
      backgroundColor: Default_Theme.themeColor.withValues(alpha: 0.3),
      destinations: [
        NavigationRailDestination(
            icon: const Icon(MingCute.home_4_fill), label: Text(l10n.navHome)),
        NavigationRailDestination(
            icon: const Icon(MingCute.book_5_fill),
            label: Text(l10n.navLibrary)),
        NavigationRailDestination(
            icon: const Icon(MingCute.search_2_fill),
            label: Text(l10n.navSearch)),
        NavigationRailDestination(
            icon: const Icon(MingCute.music_2_fill),
            label: Text(l10n.navLocal)),
        NavigationRailDestination(
            icon: const Icon(MingCute.folder_download_fill),
            label: Text(l10n.navOffline)),
      ],
      selectedIndex: navigationShell.currentIndex,
      minWidth: 70,
      onDestinationSelected: navigationShell.goBranch,
      groupAlignment: 0.0,
      selectedIconTheme: const IconThemeData(
          color: Default_Theme.onPrimaryContainerColor),
      unselectedIconTheme:
          const IconThemeData(color: Default_Theme.primaryColor2),
      indicatorColor: Default_Theme.primaryContainerColor,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
    );
  }
}

class HorizontalNavBar extends StatelessWidget {
  const HorizontalNavBar({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = <(IconData, IconData, String)>[
      (MingCute.home_4_line, MingCute.home_4_fill, l10n.navHome),
      (MingCute.book_5_line, MingCute.book_5_fill, l10n.navLibrary),
      (MingCute.search_2_line, MingCute.search_2_fill, l10n.navSearch),
      (MingCute.music_2_line, MingCute.music_2_fill, l10n.navLocal),
      (MingCute.folder_download_line, MingCute.folder_download_fill,
          l10n.navOffline),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: Default_Theme.surfaceColor.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItem(
                    selected: navigationShell.currentIndex == i,
                    icon: items[i].$1,
                    activeIcon: items[i].$2,
                    label: items[i].$3,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      navigationShell.goBranch(
                        i,
                        initialLocation: i == navigationShell.currentIndex,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: selected ? 60 : 40,
            height: 32,
            decoration: BoxDecoration(
              color: selected
                  ? Default_Theme.primaryContainerColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              selected ? activeIcon : icon,
              size: 22,
              color: selected
                  ? Default_Theme.onPrimaryContainerColor
                  : Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
