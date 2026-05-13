import 'package:yaml/yaml.dart';

class YamlUtils {
  static Map<String, dynamic> yamlToMap(dynamic yamlNode) {
    if (yamlNode is YamlMap) {
      final map = <String, dynamic>{};
      yamlNode.forEach((key, value) {
        map[key.toString()] = _convertNode(value);
      });
      return map;
    }
    if (yamlNode is Map) {
      return yamlNode.cast<String, dynamic>();
    }
    return {};
  }

  static dynamic _convertNode(dynamic node) {
    if (node is YamlMap) {
      return yamlToMap(node);
    } else if (node is YamlList) {
      return node.map((e) => _convertNode(e)).toList();
    }
    return node;
  }
}
