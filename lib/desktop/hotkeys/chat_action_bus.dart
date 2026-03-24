import 'dart:async';

enum ChatAction {
  newTopic,
  toggleLeftPanelAssistants,
  toggleLeftPanelTopics,
  focusInput,
  switchModel,
  enterGlobalSearch,
  exitGlobalSearch,
  focusInputWithText, // NEW: focus input and insert text from pending buffer
}

class ChatActionBus {
  ChatActionBus._();
  static final ChatActionBus instance = ChatActionBus._();

  final _controller = StreamController<ChatAction>.broadcast();
  Stream<ChatAction> get stream => _controller.stream;

  // Pending text payload set by fireWithText, consumed by popPendingText.
  String? _pendingText;

  void fire(ChatAction action) => _controller.add(action);

  /// Fire [ChatAction.focusInputWithText] with a text payload.
  /// The chat input widget should call [popPendingText] when handling this action.
  void fireWithText(String text) {
    _pendingText = text;
    _controller.add(ChatAction.focusInputWithText);
  }

  /// Pop (consume) the pending text payload set by [fireWithText].
  /// Returns the text and clears the buffer, or null if not set.
  String? popPendingText() {
    final t = _pendingText;
    _pendingText = null;
    return t;
  }

  void dispose() => _controller.close();
}
