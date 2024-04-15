const List<String> stopSequences = ['.', '?', '!'];

extension StringExtensions on String {
  String prepareQuestion() {
    return stopSequences.contains(this[length - 1]) ? this : '$this?';
  }
}
