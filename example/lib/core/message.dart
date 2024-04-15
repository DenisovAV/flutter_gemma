import 'package:equatable/equatable.dart';

class Message extends Equatable {
  const Message({required this.text, this.isHuman = false});

  final String text;
  final bool isHuman;

  @override
  List<Object> get props => [text, isHuman];
}
