#
# 校验补丁结果：确认所有改动都落在字符串内部，字符串之间的间隙一个字节都没动。
#
# 用法：
#   pwsh -File verify.ps1 -Original .\TrainerV.asi -Patched .\TrainerV.zh.asi
#
param(
    [Parameter(Mandatory)] [string]$Original,
    [Parameter(Mandatory)] [string]$Patched,
    [int]$RdataStart = 0xE2400,
    [int]$RdataLen   = 1483264
)

$ErrorActionPreference = 'Stop'
$a = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Original))
$b = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Patched))

if ($a.Length -ne $b.Length) { throw "文件长度不一致：$($a.Length) vs $($b.Length)（多半是传输被截断）" }

$RdataEnd = $RdataStart + $RdataLen

# 收集原文里所有字符串的 [起, 止) 区间
$spans = @()
$i = $RdataStart
while ($i -lt $RdataEnd) {
    if ($a[$i] -ge 0x20 -and $a[$i] -le 0x7E -and $a[$i - 1] -eq 0) {
        $s = $i
        while ($a[$i] -ge 0x20 -and $a[$i] -le 0x7E) { $i++ }
        if (($i - $s) -ge 3) { $spans += , @($s, $i) }
    } else { $i++ }
}

function InString([int]$off) {
    foreach ($sp in $spans) { if ($off -ge $sp[0] -and $off -lt $sp[1]) { return $true } }
    return $false
}

# 逐段比对
$runs = 0; $bytesChanged = 0; $outsideRdata = 0; $outsideString = 0
$bad = @()
$i = 0
while ($i -lt $a.Length) {
    if ($a[$i] -ne $b[$i]) {
        $s = $i
        while ($i -lt $a.Length -and $a[$i] -ne $b[$i]) { $i++ }
        $runs++
        $bytesChanged += ($i - $s)
        if ($s -lt $RdataStart -or $i -gt $RdataEnd) { $outsideRdata++; $bad += ('0x{0:X} 落在 .rdata 外' -f $s) }
        elseif (-not (InString $s)) { $outsideString++; $bad += ('0x{0:X} 不在字符串内（原文：{1}）' -f $s, [Text.Encoding]::Latin1.GetString($a, [Math]::Max(0,$s-16), 16)) }
    } else { $i++ }
}

Write-Host "长度        : $($a.Length) 字节（一致）"
Write-Host "改动段      : $runs"
Write-Host "改动字节    : $bytesChanged"
Write-Host ".rdata 外改动: $outsideRdata"
Write-Host "串区间外改动: $outsideString"
if ($runs -eq 0) { Write-Host '两份文件完全相同，没有写入任何译文。' }

if ($outsideRdata -eq 0 -and $outsideString -eq 0) {
    Write-Host '结果：PASS（全部改动都在字符串内部）'
    exit 0
} else {
    Write-Host '结果：FAIL'
    $bad | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    exit 1
}
