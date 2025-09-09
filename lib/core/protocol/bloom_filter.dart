import 'dart:math';

class BloomFilter {
  final int size;
  final int hashFunctions;
  final List<bool> _bitArray;
  int _elementsAdded = 0;

  BloomFilter(this.size, this.hashFunctions)
      : _bitArray = List<bool>.filled(size, false);

  int _hashString(String item, int seed) {
    int hash = seed;
    for (int i = 0; i < item.length; i++) {
      hash = (hash * 31 + item.codeUnitAt(i)) % size;
    }
    return hash;
  }

  void add(String item) {
    for (int i = 0; i < hashFunctions; i++) {
      int index = _hashString(item, i);
      _bitArray[index] = true;
    }
    _elementsAdded++;
  }

  bool contains(String item) {
    for (int i = 0; i < hashFunctions; i++) {
      int index = _hashString(item, i);
      if (!_bitArray[index]) {
        return false;
      }
    }
    return true; // Might be a false positive, but true negatives are guaranteed
  }

  int get length => _elementsAdded;

  void clear() {
    for (int i = 0; i < size; i++) {
      _bitArray[i] = false;
    }
    _elementsAdded = 0;
  }
}
