$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

try {
    $stdin = [Console]::In.ReadToEnd()
    $data = $stdin | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine("check-secrets.ps1: 入力の解析に失敗したため検知をスキップしました。hook設定を確認してください。")
    exit 0
}

$text = $data.tool_input.content
if (-not $text) { $text = $data.tool_input.new_string }
if (-not $text) { $text = $data.tool_input.command }
if (-not $text) { exit 0 }

$patterns = @(
    'AKIA[0-9A-Z]{16}',
    '-----BEGIN [A-Z ]*PRIVATE KEY-----',
    '(?i)(api[_-]?key|secret|token|password|passwd)\s*[:=]\s*[\"''][A-Za-z0-9/+_=\-]{12,}[\"'']',
    'xox[baprs]-[A-Za-z0-9-]{10,}'
)

foreach ($p in $patterns) {
    if ($text -match $p) {
        $reason = "シークレットらしき文字列を検知しました(パターン: $p)。意図した内容か確認してください。"
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
}

exit 0
