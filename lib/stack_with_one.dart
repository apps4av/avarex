class StackWithOne<E> {
  StackWithOne(E startElement) : _storage = <E>[startElement];
  final List<E> _storage;

  void push(E element) => _storage.add(element);
  E pop() {
    // pop last and clear the rest
    E element = _storage.removeLast();
    _storage.clear();
    // put the last back in queue so next pop will get this if no new value comes in.
    _storage.add(element);
    return (element);
  }
}