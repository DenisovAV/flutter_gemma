class Message {
  const Message({required this.text, this.isUser = false});

  final String text;
  final bool isUser;
}
