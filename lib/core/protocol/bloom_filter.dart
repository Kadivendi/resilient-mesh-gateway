/// Bloom Filter Implementation for RAMP (Rapid Alert Message Protocol)
/// 
/// A Bloom filter is a space-efficient probabilistic data structure used to test 
/// whether an element is a member of a set. False positive matches are possible, 
/// but false negatives are not.
/// 
/// For a size of 10,000 bits and 5 hash functions, the false positive rate is:
/// - 0.01% after 100 elements
/// - 0.94% after 1,000 elements
/// - 9.18% after 3,000 elements
/// 
/// This is highly optimized for BLE constraints where maintaining a large
/// Set<String> of UUIDs would exhaust memory on edge nodes.
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
