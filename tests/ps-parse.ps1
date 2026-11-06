# tests/ps-parse.ps1 —— PowerShell 脚本语法检查（GitHub Actions 与 dev 上运行，D-041）
# 用法：pwsh -NoProfile -File tests/ps-parse.ps1 bootstrap.ps1 dotfiles/.config/powershell/profile.ps1
$bad = 0
foreach ($f in $args) {
  $tokens = $null; $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) {
    $bad++
    foreach ($e in $errors) { Write-Host "FAIL ${f}:$($e.Extent.StartLineNumber): $($e.Message)" }
  } else { Write-Host "PASS $f" }
}
exit $bad
