import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class DemoPaymentScreen extends StatefulWidget {
  final String planId;
  final String planTitle;
  final String planPrice;

  const DemoPaymentScreen({
    super.key,
    required this.planId,
    required this.planTitle,
    required this.planPrice,
  });

  @override
  State<DemoPaymentScreen> createState() => _DemoPaymentScreenState();
}

class _DemoPaymentScreenState extends State<DemoPaymentScreen> {
  bool _loading = false;
  String? _error;

  String _txId() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  String _prettyFunctionsError(Object e) {
    if (e is FirebaseFunctionsException) {
      final code = e.code;
      final msg = e.message ?? 'Bilinmeyen hata';
      return '($code) $msg';
    }
    return e.toString();
  }

  Future<void> _payDemo() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ senin functions tarafın europe-west1
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = functions.httpsCallable(
        'completeDemoPaymentAndActivatePremium',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );

      final res = await callable.call(<String, dynamic>{
        'planId': widget.planId,
        'clientTxId': _txId(),
      });

      final raw = res.data;
      final data = (raw is Map)
          ? Map<String, dynamic>.from(raw as Map)
          : <String, dynamic>{};

      if (data['isPremium'] != true) {
        throw Exception('Premium aktif edilemedi (sunucu onayı yok).');
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Premium Aktif 🎉'),
          content: Text('${widget.planTitle} başarıyla aktif edildi.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true); // ✅ ödeme ekranından true ile çık
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _prettyFunctionsError(e));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ödeme (Demo)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.planTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(widget.planPrice),
            const SizedBox(height: 24),
            const Text(
              'Bu ekran demo amaçlıdır.\nGerçek ödeme alınmaz.',
              style: TextStyle(color: Colors.grey),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _payDemo,
                child: _loading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Ödemeyi Tamamla (Demo)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
