# 美坂

美坂の辞書を使うゴースト向けの、macOS 14以降用SHIORIです。Swiftで作った独立実装です。

## Utataneで使う

1. Utataneのメニューバーで「モジュール」→「モジュールカタログ…」を開きます。
2. このモジュールを選び、ダウンロードします。
3. 導入後は「機能」→「復旧操作」→「現在のゴーストを再読み込み」で、ゴーストを読み込み直します。

ゴーストにmacOS用のSHIORIが同梱されている場合は、そちらが優先されます。更新した版が使われているかは、「SHIORI読み込み診断」で確認できます。

## 手動で配置する・ゴーストへ同梱する

### 共通導入

ZIP内の `misaka-native/` を次の場所へ置きます。

```text
~/Library/Application Support/Utatane/NativeShiori/misaka-native/
```

`misaka.ini` を持つゴースト・プラグインで使われます。

### ゴーストへ同梱

ZIP内の `misaka-native/lib/libmisaka.dylib` を `ghost/master/` へ入れ、`descript.txt` に追記します。Windows用の `shiori` 指定はそのまま残します。

```text
shiori.macos,libmisaka.dylib
```

同梱版を優先し、共通導入版のダウンロードは不要です。プラグインではプラグインのフォルダへ入れ、`filename.macos,libmisaka.dylib` と指定します。再配布時はZIP内の `LICENSES/` も含めてください。

## 互換範囲

平文の美坂辞書とmacOS用SAORIに対応します。暗号化辞書は対象外です。
