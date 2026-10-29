# flutter_asset_encrypt

[English](README.md) | 中文文档

帮助开发者收集项目资源并且加密。
步骤如下：
1. 会通过扫描项目`pubspec.yaml`中的`assets` 字段收集资源
2. 通过配置的`include` `exclude`规则过滤资源集
3. 通过AES对称加密对文件进行加密，加密文件会保存到配置的`output`中，其他资源的相对路径关系及文件名都会保持不变
4. 修改项目`pubspec.yaml`文件，将原来的资源路径增加`output`配置的前缀

## 安装及使用

### 使用源码的方式

添加 `dart` 至环境变量

```bash
git clone https://github.com/yangxiaoweihn/flutter_asset_encrypt
cd flutter_asset_encrypt
dart pub get
dart bin/asset_generator.dart $flutter_project
```

### 通过 pub global 运行

1. 参阅 [pub global][] 官方文档添加 `~/.pub-cache/bin` 至环境变量下：

```bash
dart pub global activate flutter_asset_generator

# 或

dart pub global activate -s git https://github.com/yangxiaoweihn/flutter_asset_encrypt.git                 
```

1. 在项目目录下执行：

```bash
fgen
```

或者

```bash
fgen -s $flutter_project
```

### 支持的命令行参数

使用 `$ fgen -h` 或 `$ fgen --help` 可以查看帮助文档

```bash
fgen -h
-w, --[no-]watch    Continue to monitor changes after execution of orders.
                    (defaults to on)

-o, --output        The save directory for encrypted resources.
                    It's a relative path, the relative flutter root directory
                    (defaults to "/fae_xxx/")

-s, --src           Flutter project root path
                    (defaults to ".")

    --config_file   The config file path.
                    (defaults to "assets_enc_gen.yaml")
                    
  , --input_r_files The assets generator mapper files.
                    (defaults to null)
                    
  , --enc_bytes_len The bytes length for encryption.
                    (defaults to null, all bytes encrypt)

-k, --enc_key       The key used for AES encryption (128/192/256 bits).
                    (defaults to null, no encryption)
                    
  , --enc_mode      The AES encryption mode.
                    (defaults to GCM)
                     
  , --enc_padding   The AES encryption padding.
                    (defaults to PKCS7)

-h, --[no-]help     Help usage

-d, --[no-]debug    debug info
```

-s 是 flutter 目录

-o 是加密后的资源存放根文件夹名称

### 排除和导入

使用`glob`语法

其中 `exclude` 节点下为排除的文件名，类型是字符串数组，如未包含任何规则则表示不排除任何文件

`include` 表示需要导入的文件名，字符串数组，如果未包含任何规则表示允许所有

优先级方面，exclude 高于 include，换句话说：

先根据 include 节点导入文件，然后 exclude 排除文件

#### 典型示例

```yaml
exclude:
  - "**/add*.png"
  - "**_**"

include:
  - "**/a*.png"
  - "**/b*"
  - "**/c*"
```

```yaml
flutter:
  assets:
    - assets/
    - images/
```

```sh
assets
├── address.png           # exclude by "**/add*.png"
├── address@at.png        # exclude by "**/add*.png"
├── bluetoothon-fjdfj.png
├── bluetoothon.png
└── camera.png

images
├── address space.png     # exclude by "**/add*.png"
├── address.png           # exclude by "**/add*.png"
├── addto.png             # exclude by "**/add*.png"
├── audio.png
├── bluetooth_link.png    # exclude by **_**
├── bluetoothoff.png
├── child.png
└── course.png
```

加密结果:

`pubspec.yaml`
```yaml
flutter:
  assets:
    - assets/address.png
    - assets/address@at.png
    - fae_xxx/assets/a.png # bluetoothon-fjdfj.png
    - fae_xxx/assets/b.png # bluetoothon.png
    - fae_xxx/assets/c.png # camera.png

    - images/address space.png
    - images/address.png
    - images/addto.png
    - images/bluetooth_link.png
    - fae_xxx/images/d.png # audio.png
    - fae_xxx/images/e.png # bluetoothoff.png
    - fae_xxx/images/f.png # child.png
    - fae_xxx/images/g.png # course.png
```

加密结果目录:
```sh
fae_xxx/assets
├── bluetoothon-fjdfj.png
├── bluetoothon.png
└── camera.png

fae_xxx/images
├── audio.png
├── bluetoothoff.png
├── child.png
└── course.png
```

### 其他配置选项
完整的配置参数可参考：
```
 [_cfg_demo.yaml](_cfg_demo.yaml)
```
