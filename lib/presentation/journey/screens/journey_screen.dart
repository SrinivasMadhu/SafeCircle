import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/sensor_service.dart';
import '../../../core/services/battery_service.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/journey_status_card.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/journey_provider.dart';
import '../../fake_call/screens/fake_call_screen.dart';

class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  final SensorService _sensorService = SensorService();
  final BatteryService _batteryService = BatteryService();
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  bool _showFakeCall = false;

  @override
  void initState() {
    super.initState();

    // Shake to Panic listener
    _sensorService.startShakeDetection(onPanicDetected: () {
      _triggerPanicJourney();
    });

    // Battery monitoring listener
    _batteryService.startBatteryMonitoring(onCriticalBattery: (level) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Battery level critically low ($level%). Trusted contacts alerted.'),
          backgroundColor: AppColors.warning,
        ),
      );
    });

    _startTimer();
  }

  @override
  void dispose() {
    _sensorService.stopShakeDetection();
    _batteryService.stopMonitoring();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _triggerPanicJourney() async {
    final controller = ref.read(journeyControllerProvider.notifier);
    final journey = await controller.startJourney(
      destinationName: 'EMERGENCY SHAKE PANIC',
      isPanic: true,
    );

    if (mounted && journey != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency panic triggered! Live location dispatched to contacts.'),
          backgroundColor: AppColors.danger,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _startStandardJourney() async {
    final destController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Start Active Journey', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: destController,
          decoration: const InputDecoration(
            labelText: 'Destination (Optional)',
            hintText: 'e.g. Walking Home, Taxi Ride',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          CustomButton(
            text: 'Start Now',
            isFullWidth: false,
            height: 42,
            onPressed: () async {
              Navigator.of(context).pop();
              final dest = destController.text.trim();
              await ref.read(journeyControllerProvider.notifier).startJourney(
                    destinationName: dest.isNotEmpty ? dest : 'Active Journey',
                  );
            },
          ),
        ],
      ),
    );
  }

  void _confirmSafeArrival(String journeyId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 64),
            SizedBox(height: 16),
            Text(
              'Arrived Safely!',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Sending safe-arrival confirmation to trusted contacts and completing journey...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () async {
      await ref.read(journeyControllerProvider.notifier).endJourney(journeyId);
      if (mounted && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  void _oneTapQuickPing() async {
    try {
      await ref.read(journeyControllerProvider.notifier).sendQuickPing();
      final loc = await LocationService.getCurrentLocation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quick Ping Sent & Contacts Notified! (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quick Ping failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  String _formatElapsed(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final activeJourneyAsync = ref.watch(activeJourneyStreamProvider);
    final user = ref.watch(authStateProvider).value;
    final rawName = user?.displayName ?? '';
    final rawEmail = user?.email ?? '';
    final userName = rawName.isNotEmpty && rawName != 'SafeCircle User'
        ? rawName
        : (rawEmail.contains('@') ? rawEmail.split('@').first : 'User');

    if (_showFakeCall) {
      return FakeCallOverlay(
        callerName: 'Mom',
        onDismiss: () {
          setState(() {
            _showFakeCall = false;
          });
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          // Quick Ping button
          IconButton(
            icon: const Icon(Icons.share_location, color: AppColors.accent),
            onPressed: _oneTapQuickPing,
            tooltip: AppStrings.quickPing,
          ),
          // Fake Call button
          IconButton(
            icon: const Icon(Icons.phone_in_talk_outlined, color: AppColors.coral),
            onPressed: () {
              setState(() {
                _showFakeCall = true;
              });
            },
            tooltip: AppStrings.fakeCallTitle,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Greeting Header Card displaying automatically fetched Chrome/Google username
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                    backgroundImage: (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                        ? NetworkImage(user.photoUrl!)
                        : null,
                    child: (user?.photoUrl == null || user!.photoUrl!.isEmpty)
                        ? Text(
                            userName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, $userName 👋',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rawEmail.isNotEmpty ? rawEmail : 'Logged in with Google/Chrome',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: AppColors.coral, size: 22),
                    onPressed: () async {
                      await ref.read(authControllerProvider.notifier).signOut();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    tooltip: 'Sign Out',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            activeJourneyAsync.when(
              data: (activeJourney) => JourneyStatusCard(
                activeJourney: activeJourney,
                onStartJourney: _startStandardJourney,
                onEndJourney: () {
                  if (activeJourney != null) {
                    _confirmSafeArrival(activeJourney.id);
                  }
                },
                onShareLink: () {
                  if (activeJourney != null) {
                    final link = 'https://rish-2006.github.io/SafeCircle/#/track/${activeJourney.id}';
                    Clipboard.setData(ClipboardData(text: link));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.trackingLinkCopied),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                },
                elapsedTimeString: _formatElapsed(_elapsedSeconds),
              ),
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (err, stack) => JourneyStatusCard(
                activeJourney: null,
                onStartJourney: _startStandardJourney,
                onEndJourney: () {},
                onShareLink: () {},
                elapsedTimeString: '00:00',
              ),
            ),
            const SizedBox(height: 24),

            // Quick Actions Cards Grid
            const Text(
              'SAFETY SHORTCUTS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildShortcutCard(
                    title: 'Discreet Fake Call',
                    subtitle: 'Trigger instant exit call',
                    icon: Icons.phone_callback,
                    color: AppColors.coral,
                    onTap: () {
                      setState(() {
                        _showFakeCall = true;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildShortcutCard(
                    title: 'One-Tap Quick Ping',
                    subtitle: 'Share location once',
                    icon: Icons.pin_drop_outlined,
                    color: AppColors.primary,
                    onTap: _oneTapQuickPing,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            // Shake-to-panic banner notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: const [
                  Icon(Icons.vibration, color: AppColors.warning, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shake-to-Panic Active',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Shake device firmly at any time to trigger emergency journey & alerts.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) context.go('/contacts');
          if (index == 2) context.go('/history');
        },
      ),
    );
  }

  Widget _buildShortcutCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
