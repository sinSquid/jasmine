/// Tracks overlapping reader routes during pushReplacement animations.
/// Disposing an old route must not reset the new reader's system bars.
class ReaderSystemUi {
  ReaderSystemUi(this.apply);
  final void Function(bool fullscreen) apply;
  final Map<Object, bool> _readers = {};

  void attach(Object owner, bool fullscreen) {
    _readers[owner] = fullscreen;
    apply(fullscreen);
  }

  void update(Object owner, bool fullscreen) {
    if (!_readers.containsKey(owner)) return;
    _readers[owner] = fullscreen;
    if (identical(_readers.keys.last, owner)) apply(fullscreen);
  }

  void detach(Object owner) {
    _readers.remove(owner);
    apply(_readers.isEmpty ? false : _readers.values.last);
  }
}
