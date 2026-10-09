import 'web_instance_native.dart'
    if (dart.library.js_interop) 'web_instance_browser.dart' as platform;

/// Web credentials, personal caches and API access require the bootstrap's
/// document-lifetime origin lock. Native platforms have their own coordination.
void requireWebInstanceOwnership() => platform.requireWebInstanceOwnership();
