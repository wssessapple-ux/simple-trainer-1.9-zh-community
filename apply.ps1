#
# Simple Trainer 1.9 简体化打补丁脚本（MIT）
#
# 原理：TrainerV.asi 的 .rdata 段里字符串紧贴排列，每条后只跟 1 个 \0。
#       脚本按「文件偏移」逐条定位，先核对该偏移处是否确实是预期的英文原文，
#       再用「到下一个非零字节」算真实预算，写 UTF-8 译文，剩余空间补 00。
#       偏移表与版本强绑定——版本不对就拒绝执行，而不是赌。
#
# 用法：
#   pwsh -File apply.ps1 -Source .\TrainerV.asi.orig -Output .\TrainerV.zh.asi
#
# 可选：
#   -Force      跳过 MD5 校验（危险，仅调试用）
#   -Report xxx 额外输出一份逐条清单 CSV
#
param(
    [Parameter(Mandatory)] [string]$Source,
    [Parameter(Mandatory)] [string]$Output,
    [string]$Table     = (Join-Path $PSScriptRoot 'dict\zh.tsv'),
    [string]$Protected = (Join-Path $PSScriptRoot 'dict\protected.txt'),
    [string]$Report    = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ---- 目标构建的固定参数（Simple Trainer 1.9 / GTA V 1.0.463.1）----
$ExpectedSize = 2607616
$ExpectedMd5  = 'D50B44280A0602ACB9204434A06EA701'
$RdataStart   = 0xE2400     # .rdata 文件偏移
$RdataLen     = 1483264     # .rdata 长度

# ---- 校验源文件 ----
$srcPath = (Resolve-Path -LiteralPath $Source).Path
$b = [IO.File]::ReadAllBytes($srcPath)

if (-not $Force) {
    if ($b.Length -ne $ExpectedSize) {
        throw "文件大小 $($b.Length) 与预期 $ExpectedSize 不符。请确认拿到的是 Simple Trainer 1.9 原版；确认无误可加 -Force。"
    }
    $md5 = (Get-FileHash -LiteralPath $srcPath -Algorithm MD5).Hash
    if ($md5 -ne $ExpectedMd5) {
        throw "MD5 $md5 与预期 $ExpectedMd5 不符。偏移表只对这个构建有效，版本不对会写坏，已中止。"
    }
}
if ($b.Length -lt ($RdataStart + $RdataLen)) { throw '文件长度不足以覆盖 .rdata，版本不对。' }

# ---- 黑名单：与其他功能共用、改短即崩的串 ----
$ban = @()
if (Test-Path -LiteralPath $Protected) {
    $ban = @([IO.File]::ReadAllLines($Protected, [Text.Encoding]::UTF8) | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() })
}

# ---- 逐条应用偏移表 ----
$rows = @()
foreach ($line in [IO.File]::ReadAllLines($Table, [Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $p = $line.Split("`t")
    if ($p.Count -lt 3) { continue }
    $rows += , @($p[0].Trim(), $p[1], $p[2])
}
Write-Host "偏移表 $($rows.Count) 条，黑名单 $($ban.Count) 条"

$written = 0
$fail = New-Object System.Collections.Generic.List[string]
$out = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $off = [Convert]::ToInt32($row[0], 16)
    $orig = $row[1]
    $zh = $row[2]

    if ($off -lt $RdataStart -or $off -ge ($RdataStart + $RdataLen)) {
        $fail.Add("$($row[0]) 超出 .rdata 范围"); continue
    }
    if ($ban -contains $orig.TrimEnd()) { continue }

    # 读当前串
    $e = $off
    while ($b[$e] -ne 0) { $e++ }
    $cur = [Text.Encoding]::Latin1.GetString($b, $off, $e - $off)

    if ($cur -ne $orig) {
        $fail.Add("$($row[0]) 原文不符：期望 [$orig] 实际 [$cur]")
        $out.Add([pscustomobject]@{ Off = $row[0]; Text = $orig; Zh = ''; Status = '原文不符' })
        continue
    }

    # 真实预算 = 到下一个非零字节的距离 - 1
    $nz = $e
    while ($b[$nz] -eq 0) { $nz++ }
    $budget = ($nz - $off) - 1

    $bytes = [Text.Encoding]::UTF8.GetBytes($zh)
    if ($bytes.Length -gt $budget) {
        $fail.Add(("{0} [{1}] 超预算 {2}>{3}" -f $row[0], $orig, $bytes.Length, $budget))
        $out.Add([pscustomobject]@{ Off = $row[0]; Text = $orig; Zh = $zh; Status = '超预算' })
        continue
    }

    [Array]::Copy($bytes, 0, $b, $off, $bytes.Length)
    for ($k = $off + $bytes.Length; $k -lt $nz; $k++) { $b[$k] = 0 }

    $written++
    $out.Add([pscustomobject]@{ Off = $row[0]; Text = $orig; Zh = $zh; Status = '已写入' })
}

$outPath = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path (Get-Location).Path $Output }
[IO.File]::WriteAllBytes($outPath, $b)

if ($Report) {
    $repPath = if ([IO.Path]::IsPathRooted($Report)) { $Report } else { Join-Path (Get-Location).Path $Report }
    $out | Export-Csv -LiteralPath $repPath -NoTypeInformation -Encoding utf8
}

Write-Host "写入 $written 条 / 失败 $($fail.Count) 条"
if ($fail.Count) {
    $fail | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    Write-Host '存在失败项：请核对版本，不要直接拿去用。'
}
Write-Host "输出：$outPath"
Write-Host "校验：pwsh -File verify.ps1 -Original `"$srcPath`" -Patched `"$outPath`""
