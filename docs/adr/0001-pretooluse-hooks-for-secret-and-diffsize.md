# ADR-0001: PreToolUse hookでシークレット検知と差分行数上限を機械的に強制する

## ステータス（Status）
Accepted（採用済み）

## 背景（Context）
個人用CLAUDE.mdの停止条件には「シークレットの平文混入」「差分が200行を超える見込み」があるが、
CLAUDE.mdはシステムプロンプトではなくコンテキストとして渡されるため、厳密な遵守は保証されない。
この2条件は正規表現・行数カウントで機械的に検知可能なため、hookで実装する方針とした。

## 決定（Decision）
`.claude/settings.local.json` に PreToolUse hook（matcher: `Write|Edit`）を2件追加した。

- `check-secrets.ps1`: 書き込み内容（`tool_input.content` または `tool_input.new_string`）に対し、
  AWSアクセスキー、秘密鍵ヘッダ、`api_key`/`secret`/`token`/`password` への代入パターン、Slackトークンを
  正規表現で検知する。
- `check-diff-size.ps1`: 同内容の行数が200行を超えるかを判定する。

両スクリプトとも、検知時は `hookSpecificOutput.permissionDecision: "ask"` を返す。
即時拒否（`deny`）ではなく、開発者に確認を求める形にした。

PowerShellスクリプトはUTF-8 BOM付きで保存している。Windows PowerShell 5.1はBOM無しUTF-8を
正しく認識せず、日本語文字列を含む行でパースエラーになることを実機確認したため。

## 検討した代替案（Alternatives Considered）
- **`deny`で即時拒否**: 却下。テスト用のダミー鍵や、意図的に生成する大きめの設定ファイルなど、
  正当な作業を誤検知でブロックするリスクがある。確認を挟める `ask` を選んだ。
- **jqベースのbashスクリプト**: 却下。この環境に`jq`が未インストールであることを実機確認済み
  （`jq: command not found`）。PowerShellの`ConvertFrom-Json`/`ConvertTo-Json`で代替した。
- **200行判定を会話全体の累積差分で行う**: 却下。ツール呼び出しをまたいだ状態保持が必要になり
  実装が複雑化するため、まずは単一のWrite/Edit呼び出し単位の行数を近似値として採用した。

## 影響（Consequences）
- シークレット混入・200行超の変更が、Claude側の自己申告に頼らずhookで機械的に検知されるようになる。
- [要確認] 正規表現パターンは代表的な形式に限定しており、全ての秘密情報の形式を網羅しない。
- 200行判定は単一のWrite/Edit呼び出し単位のため、複数回に分けて累積200行を超えるケースは検知できない。
- 誤検知時は`ask`で止まるため、開発者が都度許可判断を求められる。誤検知が頻発する場合はパターンの
  調整が必要。

## 追記(2026-08-05): フェイルオープンの可視化とBash/PowerShell対応

運用開始後の監査で次の2点が判明し、対応した。

- **フェイルオープンの無音化**: stdinのJSON解析に失敗した場合、両スクリプトとも`exit 0`で許可していたが、
  失敗が無音だったため気付けなかった。catch節でstderrへ警告を出力するよう変更した。挙動そのもの
  (解析失敗時はexit 0で許可する)は変更していない。
- **Bash/PowerShellツールが検知対象外だった**: matcherが`Write|Edit`のみで、Bash/PowerShellツール経由の
  ファイル書き込み(heredoc等)やコミットメッセージへのシークレット混入が素通りしていた。matcherに
  `Bash|PowerShell`を追加し、両スクリプトで`tool_input.command`も検知対象に加えた。
- [要確認] `Bash`/`PowerShell`という名称がこの環境のツール名と一致することを前提にしている。
  ツール名が変わった場合はmatcherの見直しが必要。

## 追記2(2026-08-05): hookのask判定と権限モードの相互作用(未確認)

VSCode拡張のログ（`Claude VSCode.log`）で追記1の対応後を確認したところ、次が分かった。

- `check-secrets.ps1`は`Bash`ツール経由の呼び出しでも一貫して正しく`ask`を返していた。Bash/PowerShell対応は機能している。
- `settings.local.json`のmatcher変更は、セッションを再起動しなくても同一セッション内で反映されていた。追記1で挙げた「再起動して確認する」という対応は不要だった。
- ログ上、hookが`ask`を返した直後に確認ダイアログを介さず`"behavior":"allow"`で解決されているタイミングが、権限モードが`default`から`acceptEdits`に変わった直後と重なっていた。

**未確認の点**: 公式ドキュメント（[Configure permissions](https://code.claude.com/docs/en/agent-sdk/permissions)）によれば、`acceptEdits`が自動承認するのはファイル編集（Edit/Write）と特定のファイルシステム系コマンド（`mkdir`/`touch`/`rm`/`rmdir`/`mv`/`cp`/`sed`）のみで、`echo`のような非ファイル操作は「通常の権限確認が必要」と明記されている。今回自動承認されたのは`echo`コマンドであり、ドキュメント通りならacceptEditsだけでは説明がつかない。次のどちらが原因かは特定できていない。

- acceptEditsモードが、VSCode拡張の実装上（ドキュメントと異なり）hookの`ask`判定まで自動承認してしまっている
- セッション内の別の承認経路が、たまたま同じタイミングで働いた

**運用上の注意**: 原因が確定するまでは、シークレット検知などhookの`ask`判定に安全性を依存する作業では`acceptEdits`モードを避け、`default`モードで行うことを推奨する。
