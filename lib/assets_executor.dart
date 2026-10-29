import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_asset_collector/collector.dart';
import 'package:flutter_asset_encrypt/aes_simple.dart';
import 'package:path/path.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'aes_helper.dart';
import 'config.dart';
import 'logger.dart';

const String _logPrefix = 'Encrypt assets records';
const String _libTag = 'asset_encrypt_builder';

const List<String> dprs = <String>[
  '1.0x',
  '1.5x',
  '2.0x',
  '3.0x',
  '4.0x',
  '5.0x',
];

Logger logger = Logger()
  ..isDebug = true
  ..tag = 'AssetsEncrypt';

class AssetsExecutor {
  // ResourceDartBuilder(String projectRootPath, this.outputPath) {
  AssetsExecutor(this.config);

  final Config config;

  Filter? get filter => config.filter;

  bool get isWatch => config.isWatch;

  final FileWatcher _fileWatcher = FileWatcher();

  late AssetCollector _assetCollector;

  Future<void> collectAssetsAndEncrypt() async {
    writeLog('input-params: \n${formatJson(config.params)}');
    writeLog('config: ${config.toString()}');
    logger.debug('$_logPrefix for project: $projectRootPath');
    _fileWatcher
      ..stopWatch()
      ..clear();

    try {
      _assetCollector = AssetCollector(
        module: 'encrypt',
        projectRootPath: config.src,
        logFile: logFile,
        filter: config.filter,
      )..collect();
      // 过滤掉已经加密过的路径
      final List<String> allAssetsList = <String>[
        ..._assetCollector.allFileListByFilter
      ];

      _log(
        'The all resources path list is: \n${formatJson(allAssetsList)}',
        console: false,
      );

      _log('start filter resources by $outputDirName');

      final List<String> allNeedEncryptList = <String>[...allAssetsList]
        ..removeWhere((String test) {
          return test.contains('$outputDirName/');
        });
      _log(
        'The result of filter resources path list is: \n${formatJson(allNeedEncryptList)}',
        console: false,
      );

      _log('[ start encrypt resources');

      // relative path -> old:new
      final Map<String, String> proguardPathMap = <String, String>{};
      for (final String path in allNeedEncryptList) {
        final File fromFile = File(<String>[prp, path].join(separator));
        final int index = path.lastIndexOf('/');
        final String fileName = path.substring(max(index + 1, 0));
        final String parent = path.substring(0, max(index, 0));
        //'${outputDirName}${separator}${parent}${separator}$fileName';
        //'${prp}${separator}$toDir';
        final String toNewPath =
            <String>[prp, outputDirName, parent, fileName].join(separator);
        File(toNewPath).parent.createSync(recursive: true);
        if (config.encKey?.isNotEmpty ?? false) {
          try {
            final Uint8List bytes = await _encrypt(fromFile.readAsBytesSync());

            File(toNewPath).writeAsBytesSync(bytes);
            _log(
              'enc: $path -> ${toNewPath.replaceFirst(prp, '')}',
              console: true,
            );
          } catch (e) {
            print(e);
          }

          {
            String rPath =
                toNewPath.replaceFirst(prp, '').replaceAll(r'\', '/');
            rPath = rPath.substring(rPath.startsWith('/') ? 1 : 0);
            proguardPathMap[path] = rPath;
          }

          {
            /// 检测处理多分辨率图
            for (final String dpr in dprs) {
              final String rPath =
                  <String>[parent, dpr, fileName].join(separator);
              final File fromFile = File(<String>[prp, rPath].join(separator));
              if (fromFile.existsSync()) {
                final String toNewPath =
                    <String>[prp, outputDirName, rPath].join(separator);
                File(toNewPath).parent.createSync(recursive: true);
                try {
                  final Uint8List bytes =
                      await _encrypt(fromFile.readAsBytesSync());
                  File(toNewPath).writeAsBytesSync(bytes);
                  _log(
                    'enc: $rPath -> ${toNewPath.replaceFirst(prp, '')}',
                    console: true,
                  );
                } catch (e) {
                  print(e);
                  _log(e.toString());
                }
              }
            }
          }
        }
      }
      _log('end encrypt resources. ]');

      {
        // 处理可能的R文件
        final List<String>? inputRFiles = config.inputRFiles;
        inputRFiles?.forEach((String rPath) {
          final File rFile = File(rPath);
          if (!rFile.existsSync()) {
            return;
          }
          final String content = rFile.readAsStringSync();
          String newContent = content;
          proguardPathMap.forEach((String _old, String _new) {
            newContent = newContent.replaceAll('\'$_old\'', '\'$_new\'');
            newContent = newContent.replaceAll('"$_old"', '"$_new"');
          });
          rFile.writeAsStringSync(newContent);
        });
      }

      {
        // 更新pubspec.yaml
        final String? newContent = _handlePubspecYaml(proguardPathMap);
        if (null != newContent) {
          File pubFile = _pubspecYamlFile();
          if (config.dbgPubspec) {
            pubFile = File(
              '$projectRootPath$separator.dart_tool$separator.pubspec${separator}pubspec_encrypt_${config.type}.yaml',
            );
            pubFile.parent.createSync(recursive: true);
          }
          pubFile.writeAsStringSync(newContent);
        }
        // String? newContent = _handlePubspecYamlByAssetAndFonts(diffFiles);
        // String? newContent = _handlePubspecYamlOnlyAssets(diffFiles);
        // if (null != newContent) {
        //   File('$projectRootPath${separator}pubspec.g.yaml')
        //       .writeAsString(newContent);
        // }
        _log('end modify pubspec.yaml file');
      }
    } catch (e) {
      if (e is StackOverflowError && e.stackTrace != null) {
        writeLog(e.stackTrace!);
      } else {
        writeLog(e);
      }
    }
    _log('$_logPrefix finish.');
    _startWatch();
  }

  Future<Uint8List> _encrypt(Uint8List bytes) async {
    return config.encBytesLength == null
        ? AESHelper.encryptBytes(
            bytes,
            config.encKey!,
            mode: config.mode,
            padding: config.padding,
          )
        : AesPartSimple.encryptPartBytes(
            bytes,
            config.encBytesLength!,
            config.encKey!,
            mode: config.mode,
            padding: config.padding,
          );
  }

  String? _handlePubspecYaml(Map<String, String> proguardPathMap) {
    final List<String> beFilteredFiles = <String>[
      ..._assetCollector.allFileListBeforeFilter
    ]..retainWhere((String test) {
        return !_assetCollector.allFileListByFilter.contains(test);
      });

    /// asset目录一定是配置在yaml中的
    /// 所以 这里只需要将在exclude中存在的文件排除即可 剩余的是需要额外添加进去的

    final List<String> beFilteredDirs = <String>[
      ..._assetCollector.dirListBeforeFilter
    ]..retainWhere((String test) {
        return !_assetCollector.dirListByFilter.contains(test);
      });

    final List<String> diffFiles = <String>[...beFilteredFiles]
      ..removeWhere((String test) {
        test = test.replaceAll(r'\', '/');
        final String dir = test.substring(0, test.lastIndexOf('/'));
        // print('<> $test -> $dir');
        return beFilteredDirs.contains(dir);
      })
      ..removeWhere((String test) {
        return test.contains('$outputDirName/');
      });

    final YamlEditor editor = YamlEditor(_pubspecYamlFile().readAsStringSync());
    {
      // final rList = list.map((item) {
      //   return pathMap.containsKey(item)
      //       ? '${outputDirName}/$item'
      //       : item;
      // }).toList();

      final List<String> rList = <String>[];

      // 先处理被规则排除的文件
      // 这里优化以下 如果排除的是整个目录 则这里按照目录处理

      final Pair<Map<String, Set<String>>, List<String>> diffPair =
          parseGroup(projectRootPath, diffFiles);
      final List<String> fullDirs = diffPair.second;

      // final others = {...pair.first}
      //   ..removeWhere((key, _) {
      //     return fullDirs.contains(key);
      //   });

      // 部分文件完全被目录替代场景
      rList.addAll(fullDirs);

      final List<String> otherFiles = (<String, Set<String>>{...diffPair.first}
            ..removeWhere((String key, _) {
              return fullDirs.contains(key);
            }))
          .values
          .toList()
          .expand((Set<String> e) => e)
          .toList();
      // 其余分散的文件
      rList.addAll(otherFiles);

      // final aaa = [
      //   ...pair.first.keys,
      //   ...pair.first.values.expand((e) => e).toList()
      // ]..removeWhere((test) {
      //   return proguardPathMap.keys.contains(test);
      // });

      {
        final List<String> _diffExcludeAll = proguardPathMap.keys.toList()
          ..removeWhere((String test) {
            return <String>[
              ...diffPair.first.keys,
              ...diffPair.first.values.expand((Set<String> e) => e).toList()
            ].contains(test);
          });

        // 找出完整处理的目录
        final Pair<Map<String, Set<String>>, List<String>> pair =
            parseGroup(projectRootPath, _diffExcludeAll);
        rList.addAll(pair.second.map((String e) => '$outputDirName/$e'));

        final Map<String, Set<String>> otherFileMaps = <String, Set<String>>{
          ...pair.first
        }..removeWhere((String key, _) {
            return pair.second.contains(key);
          });
        final List<String> otherFiles =
            otherFileMaps.values.toList().expand((Set<String> e) {
          return e;
        }).toList();

        rList.addAll(otherFiles.map((String e) {
          return proguardPathMap[e]!;
        }).toList());
      }

      // // 先处理被规则排除的文件
      // // 这里优化以下 如果排除的是整个目录 则这里按照目录处理
      //
      // final pair = parseGroup(projectRootPath, diffFiles);
      // final fullDirs = pair.second;
      // final others = {...pair.first}..removeWhere((key, _) {
      //     return fullDirs.contains(key);
      //   });
      //
      // print('##@@@: ${_assetCollector.dirListBeforeFilter}');
      // print('##@@@: ${_assetCollector.dirListByFilter}');
      //
      // // 部分文件完全被目录替代场景
      // rList.addAll(fullDirs);
      // final otherFiles = others.values.toList().expand((e) => e).toList();
      // // 其余分散的文件
      // rList.addAll(otherFiles);
      // print(rList);
      //
      // // 处理定义在pubspec.yaml中的
      // final list = jsonDecode(jsonEncode(assetNode.value as YamlList)) as List;
      // print('list: ${list}');
      // print('fullDirs: ${fullDirs}');
      // // 移除被排除的目录|文件 剩余的就是被混淆的
      // final _tAll = [
      //   ...pair.first.keys,
      //   ...pair.first.values.expand((e) => e).toList()
      // ];
      // final proguard = [...list]..removeWhere((test) {
      //     return _tAll.contains(test);
      //   });
      // print('===============');
      // print(list);
      // print(_tAll);
      // print(proguard);
      // print('===============');
      // rList.addAll(proguard.map((item) {
      //   item = proguardPathMap[item] ?? item;
      //   return '$item';
      // }));

      editor.update(<Object?>['flutter', 'assets'], rList);

      return editor.toString();
    }
  }

  String? _handlePubspecYamlOnlyAssets(List<String> diffFiles) {
    // 特殊节点 assets: fonts:
    String preSpecialNodeLine = '';
    if (<String>[..._assetCollector.allFileListByFilter].isNotEmpty) {
      _log('start modify pubspec.yaml file');

      /// 修改pubspec.yaml
      // final pathMap = _assetCollector.allOriginalPathListInYaml.values
      //     .expand((list) => list)
      //     .toList()
      //     .asMap()
      //     .map((_, value) => MapEntry(value, value));
      final Map<String, String> pathMap =
          _assetCollector.dirListByFilter.asMap().map((int index, String v) {
        return MapEntry<String, String>(v, v);
      });
      final List<String> newContentList = <String>[];
      final List<String> lines = _pubspecYamlFile().readAsLinesSync();

      // 标记上一行是否为asset节点内容-
      final Map<String, String> tmpCacheMap = <String, String>{};
      const bool holderBreakLine = true;
      // 增加这个是为了后续逻辑简单
      if (holderBreakLine) {
        lines.add('\n');
      }
      for (String line in lines) {
        final String trimLine = line.trim();
        // 补充额外的 assets fonts

        if (tmpCacheMap.containsKey('assets-item') &&
            diffFiles.isNotEmpty &&
            !trimLine.startsWith(RegExp(r'-')) &&
            preSpecialNodeLine.startsWith('assets')) {
          final String p = tmpCacheMap['assets-item']!;

          final List<String> _lines = diffFiles.map((String path) {
            return p.replaceAll('@', '$path # Add by $_libTag');
          }).toList();
          newContentList.addAll(_lines);
          tmpCacheMap.remove('assets-item');
          // continue;
        }

        newContentList.add(line);

        if (!trimLine.startsWith('-')) {
          // newContentList.add(line);
          final String? n = _parseSpecialNode(line);
          preSpecialNodeLine = n ?? preSpecialNodeLine;
          continue;
        }

        // 找是否有注释
        final int index = line.indexOf('#');
        final String content =
            line.substring(0, index < 0 ? line.length : index);
        if (trimLine.startsWith(RegExp(r'-\s')) &&
            preSpecialNodeLine.startsWith('assets:')) {
          // asset section
          final String d = content.trim().replaceFirst('-', '').trim();
          tmpCacheMap['assets-item'] = line.replaceAll(content.trim(), '- @');

          if (pathMap.containsKey(d)) {
            line = line.replaceAll(content.trim(), '- $outputDirName/$d');
            line = line.replaceFirst('#', '# Modify by $_libTag ');
            newContentList
              ..removeLast()
              ..add(line);
          }
          continue;
        }

        final String? n = _parseSpecialNode(line);
        preSpecialNodeLine = n ?? preSpecialNodeLine;
      }

      if (holderBreakLine) {
        newContentList.removeLast();
      }
      final String newContent = newContentList.join('\n');
      // _pubspecYamlFile().writeAsString(newContent);
      return newContent;
    }
    return null;
  }

  /// 处理yaml文件内容
  /// 包含assets节点和fonts节点的处理
  /// 但是这俩同时存在在逻辑上可能会不能完全覆盖 所以逻辑不是特别完善
  /// [diffFiles] 包含所有的文件[assets fonts]
  String? _handlePubspecYamlByAssetAndFonts(List<String> diffFiles) {
    // only assets section, remove fonts
    final List<String> _tFontsList = _assetCollector.allFontsFilesBeforeFilter;
    final List<String> diffAssetsFiles = <String>[...diffFiles];
    if (_tFontsList.isNotEmpty) {
      diffAssetsFiles.removeWhere((String test) {
        return _tFontsList.contains(test);
      });
    }

    // only fonts section, remove assets
    final List<String> _tAssetsList =
        _assetCollector.allAssetsFilesBeforeFilter;
    final List<String> diffFontsFiles = <String>[...diffFiles];
    if (_tAssetsList.isNotEmpty) {
      diffFontsFiles.removeWhere((String test) {
        return _tAssetsList.contains(test);
      });
    }

    // 特殊节点 assets: fonts:
    String preSpecialNodeLine = '';
    if (<String>[..._assetCollector.allFileListByFilter].isNotEmpty) {
      _log('start modify pubspec.yaml file');

      /// 修改pubspec.yaml
      // final pathMap = _assetCollector.allOriginalPathListInYaml.values
      //     .expand((list) => list)
      //     .toList()
      //     .asMap()
      //     .map((_, value) => MapEntry(value, value));
      final Map<String, String> pathMap =
          _assetCollector.dirListByFilter.asMap().map((int index, String v) {
        return MapEntry<String, String>(v, v);
      });
      final List<String> newContentList = <String>[];
      final List<String> lines = _pubspecYamlFile().readAsLinesSync();

      // 标记上一行是否为asset节点内容-
      // moduleName -> (preLineIsAssetItem, placeHolder)
      final Map<String, String> tmpCacheMap = <String, String>{};
      const bool holderBreakLine = true;
      // 增加这个是为了后续逻辑简单
      if (holderBreakLine) {
        lines.add('\n');
      }
      for (String line in lines) {
        final String trimLine = line.trim();
        // 补充额外的 assets fonts

        // fonts section
        if (tmpCacheMap.containsKey('fonts-item') &&
            diffFontsFiles.isNotEmpty &&
            !trimLine.startsWith(RegExp(r'-')) &&
            preSpecialNodeLine.startsWith('fonts')) {
          final String p = tmpCacheMap['fonts-item']!;

          final List<String> _lines = diffFontsFiles.map((String path) {
            return p.replaceAll('@', '$path # Add by $_libTag');
          }).toList();
          newContentList.addAll(_lines);
          tmpCacheMap.remove('fonts-item');
        } else
        // assets section
        if (tmpCacheMap.containsKey('assets-item') &&
            diffAssetsFiles.isNotEmpty &&
            !trimLine.startsWith(RegExp(r'-')) &&
            preSpecialNodeLine.startsWith('assets')) {
          final String p = tmpCacheMap['assets-item']!;

          final List<String> _lines = diffAssetsFiles.map((String path) {
            return p.replaceAll('@', '$path # Add by $_libTag');
          }).toList();
          newContentList.addAll(_lines);
          tmpCacheMap.remove('assets-item');
          // continue;
        }

        // if (diffAssetsFiles.isNotEmpty &&
        //     !trimLine.startsWith(RegExp(r'-'))) {
        //
        //   if (tmpCacheMap.containsKey('fonts-item')) {
        //     // fonts section
        //     final String p = tmpCacheMap['fonts-item'] as String;
        //
        //     final _lines = diffAssetsFiles.map((path) {
        //       return p.replaceAll('@', '$path # Add by $_libTag');
        //     }).toList();
        //     newContentList.addAll(_lines);
        //     tmpCacheMap.remove('fonts-item');
        //   } else if (tmpCacheMap.containsKey('assets-item')) {
        //     // assets section
        //     final String p = tmpCacheMap['assets-item'] as String;
        //
        //     final _lines = diffAssetsFiles.map((path) {
        //       return p.replaceAll('@', '$path # Add by $_libTag');
        //     }).toList();
        //     newContentList.addAll(_lines);
        //     tmpCacheMap.remove('assets-item');
        //     // continue;
        //   }
        // }

        newContentList.add(line);

        if (!trimLine.startsWith('-')) {
          // newContentList.add(line);
          final String? n = _parseSpecialNode(line);
          preSpecialNodeLine = n ?? preSpecialNodeLine;
          continue;
        }

        // 找是否有注释
        final int index = line.indexOf('#');
        final String content =
            line.substring(0, index < 0 ? line.length : index);
        if (trimLine.startsWith(RegExp(r'-\sasset:')) &&
            (preSpecialNodeLine.startsWith('fonts:'))) {
          // font section
          final String d = content
              .trim()
              .replaceFirst('-', '')
              .replaceFirst('asset:', '')
              .trim();

          tmpCacheMap['assets-item'] =
              line.replaceAll(content.trim(), '- asset: @');

          if (pathMap.containsKey(d)) {
            line = line.replaceAll(
              content.trim(),
              '- asset: $outputDirName/$d',
            );
            line = line.replaceFirst('#', '# Modify by $_libTag ');
            newContentList
              ..removeLast()
              ..add(line);
          }
          continue;
        }
        if (trimLine.startsWith(RegExp(r'-\s')) &&
            preSpecialNodeLine.startsWith('assets:')) {
          // asset section
          final String d = content.trim().replaceFirst('-', '').trim();
          tmpCacheMap['assets-item'] = line.replaceAll(content.trim(), '- @');

          if (pathMap.containsKey(d)) {
            line = line.replaceAll(content.trim(), '- $outputDirName/$d');
            line = line.replaceFirst('#', '# Modify by $_libTag ');
            newContentList
              ..removeLast()
              ..add(line);
          }
          continue;
        }

        final String? n = _parseSpecialNode(line);
        preSpecialNodeLine = n ?? preSpecialNodeLine;
      }

      if (holderBreakLine) {
        newContentList.removeLast();
      }
      final String newContent = newContentList.join('\n');
      // _pubspecYamlFile().writeAsString(newContent);
      return newContent;
    }
    return null;
  }

  final List<String> _specialNode = <String>['assets:', 'fonts:'];

  String? _parseSpecialNode(String line) {
    final List<String> list = line.split('#');
    if (list.isEmpty) {
      return null;
    }
    return _specialNode.contains(list.first.trim()) ? list.first.trim() : null;
  }

  static File getLogFile(Config config) {
    return File('.dart_tool$separator${config.type}_assets_enc_log.txt');
  }

  File get logFile => getLogFile(config);

  String get projectRootPath => config.src;

  String get prp => projectRootPath;

  String get outputDirName => config.output;

  final bool isWriting = false;

  /// Watch all paths
  Future<void> _startWatch() async {
    if (!isWatch) {
      return;
    }
    if (_fileWatcher.watching) {
      return;
    }
    for (final String dir in _assetCollector.dirListByFilter) {
      final StreamSubscription<FileSystemEvent>? sub =
          _fileWatcher.watch(Directory(dir), onData: (_) async {
        config.refresh();
        await collectAssetsAndEncrypt();
      });
      if (sub != null) {
        sub.onDone(sub.cancel);
      }
    }
    final File pubspec = _pubspecYamlFile();
    // ignore: cancel_subscriptions
    _fileWatcher.watch(pubspec);

    final File configFile = File(config.configFilePath);
    if (configFile.existsSync()) {
      // ignore: cancel_subscriptions
      _fileWatcher.watch(configFile);
    }

    _log('Watching all resources file.');
  }

  File _pubspecYamlFile() {
    return File('$projectRootPath${separator}pubspec.yaml');
  }

  /// Write logs to the file
  /// Defaults to `.dart_tool$separator${config.type}_assets_enc_log.txt`
  void writeLog(Object text, {File? file}) {
    file ??= logFile;
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    file
      ..writeAsStringSync(DateTime.now().toString(), mode: FileMode.append)
      ..writeAsStringSync('  : $text', mode: FileMode.append)
      ..writeAsStringSync('\n', mode: FileMode.append);
  }

  void _log(String message, {bool console = true, bool file = true}) {
    if (console) {
      logger.debug(message);
    }
    if (file) {
      writeLog(message);
    }
  }
}
