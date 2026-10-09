import 'dart:js_interop';

@JS('lifeguideInstanceOwned')
external bool? get _instanceOwned;

void requireWebInstanceOwnership() {
  if (_instanceOwned != true) {
    throw StateError('LifeGuide web instance does not own its origin lock');
  }
}
