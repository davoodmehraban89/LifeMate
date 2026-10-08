import 'package:http/http.dart' as http;
import 'runtime_http_client_native.dart'
    if (dart.library.js_interop) 'runtime_http_client_web.dart' as platform;

http.Client createRuntimeHttpClient() => platform.createClient();
