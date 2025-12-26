import 'package:flutter/material.dart';

Future<String?> showCityPickerSheet(BuildContext context) async {
  final ctrl = TextEditingController();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.of(ctx).viewInsets.bottom;

      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Konum alınamadı", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                "Şehrini elle yaz, yine öneri alırsın.",
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.75)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: "Şehir",
                  hintText: "İstanbul",
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      child: const Text("Vazgeç"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      child: const Text("Kaydet"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
