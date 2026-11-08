import 'dart:convert';

import 'package:flutter/services.dart';

typedef ChatMessage = ({bool fromUser, String text});

class SavedChat {
  SavedChat({
    required this.id,
    required this.title,
    required this.modelUri,
    required this.modelName,
    required this.messages,
  });

  final String id;
  String title;
  String modelUri;
  String modelName;
  final List<ChatMessage> messages;

  factory SavedChat.fromJson(Map<String, dynamic> value) => SavedChat(
    id: value['id'] as String,
    title: value['title'] as String,
    modelUri: value['modelUri'] as String,
    modelName: value['modelName'] as String,
    messages: [
      for (final raw in value['messages'] as List)
        (
          fromUser: (raw as Map)['fromUser'] as bool,
          text: raw['text'] as String,
        ),
    ],
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'modelUri': modelUri,
    'modelName': modelName,
    'messages': [
      for (final message in messages)
        {'fromUser': message.fromUser, 'text': message.text},
    ],
  };
}

class ChatStore {
  static const _channel = MethodChannel('portpotato/chats');

  Future<List<SavedChat>> read() async {
    final raw = await _channel.invokeMethod<String>('read');
    if (raw == null || raw.isEmpty) return [];
    return [
      for (final value in jsonDecode(raw) as List)
        SavedChat.fromJson(Map<String, dynamic>.from(value as Map)),
    ];
  }

  Future<void> write(List<SavedChat> chats) => _channel.invokeMethod<void>(
    'write',
    jsonEncode([for (final chat in chats) chat.toJson()]),
  );
}
