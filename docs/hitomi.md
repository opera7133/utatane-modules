# ひとみ。（Native 部分互換版）

ひとみ。Phase 0.2のC++ソースと、0.4系の公開資料・原作DLLを元にしたmacOS用SHIORIです。0.3.0は、条件分岐・PSY・単語学習へ対応を広げた試験版です。

## 試す

配布カタログへの公開後は、Utataneの「モジュール」→「モジュールカタログ…」から導入できます。手動で試す場合は、ZIPの`hitomi/lib/libhitomi.dylib`をゴーストの`ghost/master/`へ置き、`descript.txt`へ追記します。`LICENSES/`も一緒に配置してください。

```text
shiori.macos,libhitomi.dylib
```

読み込む辞書は`hitomi.ini`、省略時は初期版の`kawari.ini`で指定します。平文はUTF-8またはCP932、暗号化行は`!KAWA0000`形式を扱います。

```text
dict: ai.txt
```

## 互換範囲

基本の会話、条件付き辞書、PSYの一部、単語学習、タイマーに対応します。原作の保存を初回に取り込みます。学習の細かな挙動には互換差があります。外部SAORIは対象外です。

配布には同梱のBSD・MITライセンスが適用されます。
