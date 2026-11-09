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

辞書の例です。

```text
word: 日本語
?#OnBoot: \0${word}で起動したよ。\e
?#OnMouseDoubleClick "head": 頭を触ったね。\e
?#OnMouseDoubleClick .: そこ？\e
sentence: 普段のトーク。\e
```

## 対応範囲

- 初期版の辞書・イベント・局所キー・番号参照、同名キーへの追加、複数キーへの同時登録
- 条件の連結、存在・空リスト・包含・部分文字列・数値の比較、キーワードによる候補選択と既定候補
- 引用符付きのアトム、列挙・和集合・積集合、`#define`・`#undef`・`#if0`・`#if1`・`#ifdef`・`#ifndef`・`#else`・`#endif`
- PSYの`Join`・`Length`・`First`・`Rest`、`Get`・`Inc`・`Dec`・`Reset`、`SetWord`・`KillWords`・`Tmp`
- Heartsの単語・人物登録、存在確認、関連付けと照会、好き嫌いの設定・抽出、名前の通知
- `Hearts.Load`・`Random`・`RelationHolder`・`CommonRelation`の通常・Words・Friends版と`Hearts.Study`
- `MakeDateString`と`psy.ini`の`dateForm`、`UserName`、`SetTimer`・`ResetTimer`
- SHIORI/3.0の`OnTeach`による単語学習と311・312応答

保存単語は`${~Word.名前}`で参照します。同じ応答中の参照は応答開始時の値を使うので、`SetWord`の結果は次の要求から表示されます。`Get`などの命令は実行時の状態を読みます。Reference・保存単語の内容は表示データとして扱います。

`OnTeach`はReference0を覚える語、Reference1以降を関連語の入力履歴として扱います。原作のSHIORI/2.4 `TEACH`（Wordヘッダ＋Reference履歴）をこの入口へ接続したものです。空の最新入力で確定し、同じ語を関連語に指定した場合は312、追加情報を求める場合は311を返します。応答本文は`?#HitomiStudyNewWord`などの辞書で定義します。

## 保存を引き継ぐ

Native側の保存がまだない初回に、`hitomi.dat`のカウンター・保存単語・文字列リソースと、`psy.ini`の`Hearts.dict`で指定された記憶辞書を読み込みます。以後、カウンター・保存単語・Heartsの状態は`hitomi-native-state.json`へ保存します。壊れた保存はロードエラーになります。

`UTATANE_GHOST_STATE_DIR`がある場合はその配下、`HITOMI_STATE_PATH`では指定した絶対パスを使います。Utataneから使う場合はゴースト外の保存先が渡されます。原作ファイルは初回の取り込み元として保持され、Native側の状態と分けて管理されます。原作へ戻す双方向の保存互換は今後の対応範囲です。

## 互換差と今後の範囲

0.4.6の配布ゴースト全体を動かせる版としては、引き続き検証が必要です。PSYの好感度伝播、忘却・短期記憶の昇格、全字句解析、チェイン会話、外部プラグイン、WindowsのFMO・HWND・DirectSSTP・SAORIは今後の対応範囲です。`Hearts.Short.*`の設定値による自動整理もこの範囲に含みます。構文や設定の非対応部分はロード時、未対応PSY命令は実行時にエラーになります。

条件式の`empty`などは旧資料に基づく対応を含みます。引用符付きの値・複雑なリスト展開・未定義語・`First` / `Rest`では、原作の制御バイトや空応答と結果が変わる場合があります。通常の文字列としての表示、リストの先頭・残りの取得はNative側のテストで確認しています。乱数列とすべての演算式の一致は今後の検証範囲です。

学習の複合ケースでは、原作が同一起動中に返した関連語を保存ファイルへ記録せず、再起動後の照会が空になる挙動を観測しました。Native版は確定した関連を保存して保持するため、この差を残しています。明示的な好き嫌いと関連付けに対応する段階で、PSY全体の感情モデルの再現とは区別しています。

## 確認した動作

原作0.2との平文・暗号化辞書の16要求に加え、2026-11-09に原作0.4.6で条件式・PSY・学習・再起動の合成辞書を比較しました。2026-11-09の拡張比較には日時整形・一時命令・ユーザー名変更・関連保有語・Studyも含みます。42要求中41要求が一致し、残る1要求は上記の再起動後の関連語保持の差です。比較にはDLLの一時コピーを使用しています。

単体テスト、ZIPを移動してからのABI検証、Utataneの実プロセスホストでの311応答・学習確定・保存後の再起動を確認しています。画面操作と後期版ゴースト全体の動作は今後の検証範囲です。

参照資料：

- [作者の配布ページ](https://web.archive.org/web/20100301000000/http://fetish-jp.org/sakura/hitomi-dll.shtml)
- [0.3.2の条件式・リスト・PSYの説明](https://web.archive.org/web/20100301000000/http://fetish-jp.org/sakura/dll/updates032.txt)
- [0.4.0の学習とHeartsの説明](https://web.archive.org/web/20100301000000/http://fetish-jp.org/sakura/dll/updates040b.txt)

## 配布条件

ひとみ。のHolonicsと、元になった華和梨のNAKAUE.TによるBSD条件を引き継いでいます。原文を`LICENSES/Hitomi-BSD.txt`へ同梱しています。Native版の追加コードにはリポジトリのMITライセンスも適用されます。

## タイマーと追加PSY

`$SetTimer{"2","#Tick"}`は2秒経過後の`OnSecondChange`から`?#Tick`を一度呼びます。イベント名を省略すると`?#HitomiTimer`になります。`$ResetTimer{}`で待機中のタイマーを解除します。タイマーは起動中の状態です。元DLLの既定イベント・一度だけの発火・解除を合成辞書で確認しています。複数タイマーが同時に満期になる場合や会話中の抑止条件の一致は追加検証の範囲です。

`Hearts.Load`は記憶内の語の一覧を返す命令です。`RelationHolder`は引数のうち関連語を持つ語、`CommonRelation`は複数の引数に共通する関連語を返します。`Hearts.Study`は先頭の語へ続く既知語を関連付けます。原作の保存で使われる`Friend:`形式も取り込めます。`Tmp`の出力は空です。`UserName`の変更は次の要求から`${username}`と`${~String.username}`へ反映します。

原作の好感度は関連する語によって自動更新されますが、単純な加算では説明できない結果があり、更新式の確定が必要です。短期記憶の整理・昇格、`OneSideRelation`の全条件、`PlainSSTP`の制御バイト、SAORIの呼び出し構文も調査中です。元DLLへの合成SAORIの読み込み成功と、辞書からの呼び出し成功は別の段階として扱っています。
