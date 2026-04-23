import 'dart:io';
import 'dart:convert';

void main() async {
  var packageConfigFile = File('.dart_tool/package_config.json');
  if (!packageConfigFile.existsSync()) {
    print('No package_config.json file found. Please run "flutter pub get" first.');
    return;
  }
  
  var content = packageConfigFile.readAsStringSync();
  var json = jsonDecode(content);
  var packages = json['packages'] as List;
  
  int counter = 0;
  for (var package in packages) {
    String name = package['name'];
    String rootUri = package['rootUri'];
    
    String path;
    try {
      path = Uri.parse(rootUri).toFilePath();
    } catch (_) {
      continue;
    }
    
    var androidDir = Directory('$path/android');
    if (androidDir.existsSync()) {
      var buildGradle = File('${androidDir.path}/build.gradle');
      if (buildGradle.existsSync()) {
        if (fixBuildGradle(buildGradle, name, androidDir.path)) counter++;
      }
      var buildGradleKts = File('${androidDir.path}/build.gradle.kts');
      if (buildGradleKts.existsSync()) {
        if (fixBuildGradle(buildGradleKts, name, androidDir.path, true)) counter++;
      }
    }
  }
  print('Successfully patched $counter plugins with missing namespaces.');
}

bool fixBuildGradle(File file, String pluginName, String androidPath, [bool isKts = false]) {
  var content = file.readAsStringSync();
  
  if (content.contains(RegExp(r'namespace\s+'))) {
    return false; // Already has namespace
  }
  if (content.contains(RegExp(r'namespace\s*='))) {
    return false; // Already has namespace (KTS)
  }
  
  String? namespace;
  var manifestUrl = '$androidPath/src/main/AndroidManifest.xml';
  var manifest = File(manifestUrl);
  if (manifest.existsSync()) {
    var manifestContent = manifest.readAsStringSync();
    var match = RegExp(r'package="([^"]+)"').firstMatch(manifestContent);
    if (match != null) {
      namespace = match.group(1);
    }
  }
  
  namespace ??= 'com.example.${pluginName.replaceAll("-", "_")}';
  
  var regex = RegExp(r'android\s*\{');
  if (regex.hasMatch(content)) {
    var quote = isKts ? '"' : '\'';
    var injection = isKts ? 'namespace = $quote$namespace$quote' : 'namespace $quote$namespace$quote';
    var newContent = content.replaceFirst(regex, 'android {\n    $injection');
    file.writeAsStringSync(newContent);
    print('Fixed $pluginName: added $namespace');
    return true;
  }
  return false;
}
