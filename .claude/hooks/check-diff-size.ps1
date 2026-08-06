$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

try {
    $stdin = [Console]::In.ReadToEnd()
    $data = $stdin | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine("check-diff-size.ps1: 入力の解析に失敗したため検知をスキップしました。hook設定を確認してください。")
    exit 0
}

$text = $data.tool_input.content
if (-not $text) { $text = $data.tool_input.new_string }
if (-not $text) { $text = $data.tool_input.command }
if (-not $text) { exit 0 }

$lineCount = ($text -split "`n").Count
if ($lineCount -gt 200) {
    $reason = "この変更は約${lineCount}行あり、200行の上限を超えています。分割を検討してください。"
    $out = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "ask"
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Compress
    Write-Output $out
    exit 0
}

exit 0
