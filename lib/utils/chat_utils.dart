// lib/utils/chat_utils.dart

String buildChatId(String uid1, String uid2) {
  final ids = [uid1, uid2]..sort(); // alfabetik sırala
  return ids.join('_'); // örn: "uidA_uidB"
}
