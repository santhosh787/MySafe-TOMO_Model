import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/app_services.dart';

class GuardianPairingScreen extends StatefulWidget {
  const GuardianPairingScreen({required this.user, super.key});
  final User user;

  @override
  State<GuardianPairingScreen> createState() => _GuardianPairingScreenState();
}

class _GuardianPairingScreenState extends State<GuardianPairingScreen> {
  String? _invitePayload;
  bool _creating = false;
  bool _accepting = false;

  Future<void> _createInvite() async {
    setState(() => _creating = true);
    try {
      final payload = await GuardianService.instance.createInvite();
      if (mounted) setState(() => _invitePayload = payload);
    } catch (e) {
      _showMessage('Could not create invitation: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _scanInvite() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
    if (value == null || !mounted) return;
    setState(() => _accepting = true);
    try {
      await GuardianService.instance.acceptInvite(value);
      _showMessage('Guardian pairing completed.');
    } catch (e) {
      _showMessage('Could not accept invitation: $e');
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final outgoing = FirebaseFirestore.instance
        .collection('guardianLinks')
        .where('userUid', isEqualTo: widget.user.uid)
        .where('status', isEqualTo: 'active')
        .snapshots();
    final incoming = FirebaseFirestore.instance
        .collection('guardianLinks')
        .where('guardianUid', isEqualTo: widget.user.uid)
        .where('status', isEqualTo: 'active')
        .snapshots();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Trusted guardians', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Pair only with people you know and trust. The other person must sign in with a verified phone number to accept an invitation.'),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.qr_code_2_rounded, color: Color(0xFF176B68)), SizedBox(width: 9), Text('Invite a guardian', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
              const SizedBox(height: 8),
              const Text('Create a one-time QR invitation. It expires after 15 minutes and can be accepted only once.', style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 14),
              if (_invitePayload != null) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: QrImageView(data: _invitePayload!, size: 190, backgroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(child: Text('Ask your trusted person to scan this code.', style: TextStyle(fontSize: 12, color: Colors.black54))),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: _creating ? null : _createInvite,
                icon: _creating ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_link_rounded),
                label: Text(_invitePayload == null ? 'Generate pairing QR' : 'Generate a new invitation'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _accepting ? null : _scanInvite,
          icon: _accepting ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan a guardian invitation'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 22),
        Text('People you protect', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _LinkList(stream: outgoing, currentUid: widget.user.uid, outgoing: true),
        const SizedBox(height: 18),
        Text('People protecting you', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _LinkList(stream: incoming, currentUid: widget.user.uid, outgoing: false),
        const SizedBox(height: 12),
        const Text('QR invitations contain a short-lived secret. Share them privately and never post them publicly.', style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.45)),
      ],
    );
  }
}

class _LinkList extends StatelessWidget {
  const _LinkList({required this.stream, required this.currentUid, required this.outgoing});
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String currentUid;
  final bool outgoing;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Unable to load guardian links.', style: TextStyle(color: Colors.black54));
          if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(15), child: Text('No active pairings yet.', style: TextStyle(color: Colors.black54))));
          return Column(
            children: docs.map((doc) {
              final data = doc.data();
              final otherName = outgoing
                  ? (data['guardianName'] ?? data['guardianPhone'] ?? 'Guardian').toString()
                  : (data['ownerName'] ?? 'My Safe Tomo user').toString();
              final otherDetail = outgoing
                  ? (data['guardianPhone'] ?? '').toString()
                  : (data['ownerEmail'] ?? '').toString();
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFE5F2EF), child: Icon(Icons.verified_user_outlined, color: Color(0xFF176B68))),
                  title: Text(otherName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(otherDetail.isEmpty ? 'Verified pairing' : otherDetail),
                  trailing: const Icon(Icons.check_circle, color: Color(0xFF23845C)),
                ),
              );
            }).toList(),
          );
        },
      );
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan guardian QR')),
        body: Stack(
          children: [
            MobileScanner(
              onDetect: (capture) {
                if (_handled) return;
                final values = capture.barcodes
                    .map((barcode) => barcode.rawValue)
                    .whereType<String>()
                    .toList();
                final value = values.isEmpty ? null : values.first;
                if (value == null) return;
                _handled = true;
                Navigator.of(context).pop(value);
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.68), borderRadius: BorderRadius.circular(15)),
                child: const Text('Place the QR code inside the camera frame.', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      );
}
