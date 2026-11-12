import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/app_services.dart';
import '../utils/safety_math.dart';
import 'guardian_pairing_screen.dart';

class SafetyHome extends StatefulWidget {
  const SafetyHome({required this.user, super.key});
  final User user;

  @override
  State<SafetyHome> createState() => _SafetyHomeState();
}

class _SafetyHomeState extends State<SafetyHome> {
  int _tab = 0;
  bool _motionEnabled = false;
  StreamSubscription<AccelerometerEvent>? _motionSubscription;
  DateTime _lastImpactPrompt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _impactPromptOpen = false;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    try {
      await ProfileService.instance.ensureProfile(widget.user);
      await NotificationService.instance.syncCurrentToken();
    } catch (_) {
      // The signed-in UI remains usable when optional profile or push setup is offline.
    }
  }

  @override
  void dispose() {
    _motionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleMotion(bool value) async {
    setState(() => _motionEnabled = value);
    await _motionSubscription?.cancel();
    _motionSubscription = null;
    if (!value) return;
    _motionSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      final magnitude = SafetyMath.accelerationMagnitude(event.x, event.y, event.z);
      final now = DateTime.now();
      if (magnitude >= SafetyMath.impactCandidateThreshold &&
          now.difference(_lastImpactPrompt) > const Duration(seconds: 20) &&
          !_impactPromptOpen) {
        _lastImpactPrompt = now;
        _showImpactCheck(magnitude);
      }
    }, onError: (_) {
      if (mounted) setState(() => _motionEnabled = false);
    });
  }

  Future<void> _showImpactCheck(double magnitude) async {
    _impactPromptOpen = true;
    if (!mounted) return;
    final shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sudden movement detected'),
        content: Text(
          'A movement spike was detected (${magnitude.toStringAsFixed(1)} m/s²). Are you okay? '
          'Movement alone cannot determine whether an emergency has occurred.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("I'm safe"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    _impactPromptOpen = false;
    if (shouldSend == true && mounted) await _sendSos();
  }

  Future<void> _sendSos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send an SOS alert?'),
        content: const Text(
          'Your trusted guardians will be notified. Your current location will be attached only if location permission is granted and GPS is available.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.sos_rounded),
            label: const Text('Send SOS'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final id = await SafetyService.instance.createSosIncident();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SOS recorded. Incident ID: ${id.substring(0, 8)}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record SOS: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _OverviewPage(
        user: widget.user,
        motionEnabled: _motionEnabled,
        onMotionChanged: _toggleMotion,
        onSendSos: _sendSos,
        onCheckIn: () async {
          try {
            await SafetyService.instance.checkIn();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Safety check-in saved.')));
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check-in failed: $e')));
          }
        },
      ),
      GuardianPairingScreen(user: widget.user),
      _ActivityPage(user: widget.user),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Safe Tomo', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async => AuthService.instance.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield_rounded), label: 'Safety'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people_rounded), label: 'Guardians'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Activity'),
        ],
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({
    required this.user,
    required this.motionEnabled,
    required this.onMotionChanged,
    required this.onSendSos,
    required this.onCheckIn,
  });
  final User user;
  final bool motionEnabled;
  final ValueChanged<bool> onMotionChanged;
  final VoidCallback onSendSos;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim().split(' ').first
        : 'there';
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Text('Hello, $name', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Your safety circle is one tap away.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        Card(
          color: const Color(0xFFE8F3F1),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.shield_moon_rounded, size: 38, color: Color(0xFF176B68)),
                const SizedBox(height: 9),
                Text('Need help right now?', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Send your trusted guardians an emergency alert.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onSendSos,
                    icon: const Icon(Icons.sos_rounded),
                    label: const Text('SEND SOS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB3261E),
                      minimumSize: const Size.fromHeight(58),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Color(0xFFE5F2EF), child: Icon(Icons.check_circle_outline, color: Color(0xFF176B68))),
                const SizedBox(width: 13),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Safety check-in', style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(height: 3), Text('Let your circle know you are okay.', style: TextStyle(fontSize: 12, color: Colors.black54))])),
                TextButton(onPressed: onCheckIn, child: const Text("I'm safe")),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Device awareness', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        StreamBuilder<List<ConnectivityResult>>(
          stream: Connectivity().onConnectivityChanged,
          builder: (context, snapshot) {
            final results = snapshot.data ?? const [ConnectivityResult.none];
            final connected = results.any((r) => r != ConnectivityResult.none);
            return _StatusCard(
              icon: Icons.wifi_tethering_rounded,
              title: 'Network connectivity',
              subtitle: connected ? 'A network interface is available' : 'No network interface detected',
              status: snapshot.connectionState == ConnectionState.waiting ? 'Checking' : connected ? 'Available' : 'Offline',
              active: connected,
            );
          },
        ),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile.adaptive(
            value: motionEnabled,
            onChanged: onMotionChanged,
            secondary: const CircleAvatar(backgroundColor: Color(0xFFE5F2EF), child: Icon(Icons.sensors_rounded, color: Color(0xFF176B68))),
            title: const Text('Foreground motion check', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Detects a sudden movement candidate while this screen is open. It asks you before sending an alert.', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 12),
        const _InfoNote(
          text: 'This MVP monitors motion and network state only while the app is open. Network loss is not treated as proof of danger. No silent camera or microphone capture is performed.',
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.title, required this.subtitle, required this.status, required this.active});
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final bool active;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: active ? const Color(0xFFE5F2EF) : const Color(0xFFFFF1E8),
            child: Icon(icon, color: active ? const Color(0xFF176B68) : const Color(0xFF9B5A25)),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? const Color(0xFF176B68) : const Color(0xFF9B5A25))),
        ),
      );
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFFF5E8), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 19, color: Color(0xFF9B5A25)),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF6D4B2A)))),
        ]),
      );
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    final links = FirebaseFirestore.instance
        .collection('guardianLinks')
        .where('guardianUid', isEqualTo: user.uid)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: links,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load guardian activity: ${snapshot.error}'));
        }
        final activeLinks = (snapshot.data?.docs ?? [])
            .where((doc) => doc.data()['status'] == 'active')
            .toList();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text('Safety activity', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Your SOS events and activity shared by people who paired with you.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 18),
            _IncidentFeed(ownerUid: user.uid, title: 'My SOS events'),
            for (final link in activeLinks) ...[
              const SizedBox(height: 18),
              _IncidentFeed(
                ownerUid: link.data()['userUid'] as String,
                title: "${link.data()['ownerName'] ?? 'Trusted person'} — SOS events",
              ),
            ],
          ],
        );
      },
    );
  }
}

class _IncidentFeed extends StatelessWidget {
  const _IncidentFeed({required this.ownerUid, required this.title});
  final String ownerUid;
  final String title;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('incidents')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('Activity unavailable for this account.', style: TextStyle(color: Colors.black54));
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(15), child: Text('No SOS events recorded.', style: TextStyle(color: Colors.black54))));
            return Column(
              children: docs.map((doc) {
                final data = doc.data();
                final timestamp = data['createdAt'] as Timestamp?;
                final date = timestamp?.toDate().toLocal().toString() ?? 'Syncing time…';
                final location = data['location'];
                final hasLocation = location is Map && location['latitude'] != null && location['longitude'] != null;
                final locationText = hasLocation
                    ? 'GPS: ${(location['latitude'] as num).toStringAsFixed(5)}, ${(location['longitude'] as num).toStringAsFixed(5)}'
                    : 'No location attached';
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFFFFE9E7), child: Icon(Icons.sos_rounded, color: Color(0xFFB3261E))),
                    title: Text((data['type'] ?? 'Safety event').toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    subtitle: Text('$date\n$locationText', style: const TextStyle(fontSize: 12, height: 1.5)),
                    isThreeLine: true,
                    trailing: Text((data['status'] ?? 'open').toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
