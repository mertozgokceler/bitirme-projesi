import 'package:flutter/material.dart';

import '../services/ai_career_service.dart';
import '../theme/app_colors.dart';

class AiCareerAdvisorSheet extends StatefulWidget {
  const AiCareerAdvisorSheet({super.key});

  @override
  State<AiCareerAdvisorSheet> createState() => _AiCareerAdvisorSheetState();
}

class _AiCareerAdvisorSheetState extends State<AiCareerAdvisorSheet> {
  final TextEditingController _controller = TextEditingController();
  final List<_AiMessage> _messages = [];
  bool _isSending = false;

  final _service = AiCareerService();

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _AiMessage(
        fromUser: false,
        text: 'Merhaba, ben TechConnect AI Career Advisor.\n'
            'Bana şunları sorabilirsin:\n'
            '- Hangi pozisyon bana uygun?\n'
            '- CV’mi nasıl iyileştiririm?\n'
            '- Hangi skill’leri öğrenmeliyim?\n'
            '- Bugün hangi şirkete başvurayım?',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _messages.add(_AiMessage(fromUser: true, text: text));
      _controller.clear();
    });

    try {
      final reply = await _service.ask(text);
      if (!mounted) return;
      setState(() {
        _messages.add(_AiMessage(fromUser: false, text: reply));
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.sheetHandle(theme),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'AI Career Advisor',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];

                  final align =
                  m.fromUser ? Alignment.centerRight : Alignment.centerLeft;

                  final bubble = m.fromUser
                      ? AppBubbleStyle.user(theme)
                      : AppBubbleStyle.ai(theme);

                  return Align(
                    alignment: align,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: bubble.decoration,
                      child: Text(
                        m.text,
                        style: TextStyle(color: bubble.textColor),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Kariyerinle ilgili bir soru yaz...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiMessage {
  final bool fromUser;
  final String text;

  const _AiMessage({required this.fromUser, required this.text});
}
