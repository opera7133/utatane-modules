# pasta

ZIP内の `pasta/lib/libpasta.dylib` を `ghost/master/` に置きます。Utataneでは既存の`descript.txt`の指定をそのまま使えます。

```text
shiori,pasta.dll
```

他のベースウェアで必要なら`shiori.macos,libpasta.dylib`を追加してください。

`LICENSES/` も含めて同梱してください。共通導入の場合は、ZIP内の `pasta/` を `~/Library/Application Support/Utatane/NativeShiori/` に置きます。

LuaJITと標準Pastaスクリプトはdylibに含まれます。辞書・保存先は `pasta.toml` に従い、保存データの既定位置はゴースト内の `profile/pasta/save/` です。Windows専用のLua FFI呼び出しやDLLは実行できません。

文字列はUTF-8です。Utataneではゴーストごとに別プロセスで実行します。
