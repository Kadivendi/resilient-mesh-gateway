# Contributing to Resilient Mesh Gateway

## Development Setup

```bash
flutter pub get
flutter run
```

## Testing

```bash
# Unit tests
flutter test

# Specific test file
flutter test test/routing_algorithm_test.dart

# Mesh simulation
dart run test/simulation/mesh_simulator.dart --nodes 5
```

## Code Style

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use doc comments (`///`) on all public APIs
- Prefer `final` for immutable fields
- Use named constructors for clarity

## Commit Conventions

```
feat(scope): add new feature
fix(scope): fix bug description
test(scope): add or update tests
docs(scope): documentation changes
```

### Scopes
`mesh`, `ble`, `wifi`, `lora`, `crypto`, `routing`, `battery`, `storage`, `peer`
