# flutter_asset_encrypt

English | [中文文档](README_CHN.md)

The purpose of this library is to help flutter developers
automatically encrypt assets.
To help developers release their hands from this meaningless job,
and the open source community has a lot of the same functionality.

The steps are as follows:
1. Collect resources by scanning `assets` field in the project's `pubspec.yaml` file.
2. Filter the resource set based on the configured `include` and `exclude` rules.
3. Encrypt the files using AES symmetric encryption. The encrypted files will be saved to the configured `output` path, while the relative paths and filenames of other resources remain unchanged.
4. Modify the project's `pubspec.yaml` file by adding the `output` configuration prefix to the original resource paths.


## Usage

### Run from source

Add `dart` to your `$PATH` environment.

```bash
git clone https://github.com/yangxiaoweihn/flutter_asset_encrypt
cd flutter_asset_encrypt
dart pub get
dart bin/asset_generator.dart $flutter_project
```

### Run from pub global

1. Install using [pub global][]:

### Support options

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

### exclude and include rules

The file is yaml format, every element is `glob` style.

The name of the excluded file is under the `exclude` node, and the type is a string array. If no rule is included, it means no file is excluded.

The `include` node is the name of the file that needs to be imported, and the type is a string array. If it does not contain any rules, all file are allowed.

In terms of priority, exclude is higher than include, in other words:

First import the file according to the include nodes, and then exclude the files.

#### Example

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

encrypt result:

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

encrypt dist files: 
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

### Other
Full config: 
```
 [_cfg_demo.yaml](_cfg_demo.yaml)
```