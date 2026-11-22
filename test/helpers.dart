import 'dart:convert';
import 'dart:io';

import 'package:u4/config/app_config.dart';

/// 번들된 [flavor] 설정 파일을 JSON으로 읽는다.
Map<String, Object?> readConfigJson(Flavor flavor) =>
    jsonDecode(File(flavor.assetPath).readAsStringSync())
        as Map<String, Object?>;
