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

# ---- 译文内容检查：必须是合法 UTF-8，且不得出现乱码字符 ----
# 允许：ASCII 可见字符、CJK 标点(3000-303F)、汉字(4E00-9FFF)、全角(FF00-FFEF)，
#       以及中文引号 / 间隔号等常见标点。
# 拒绝：U+FFFD（替换符）、控制字符、U+0080-U+00FF（Latin-1 乱码高发区）、私用区。
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$noise = @()
$checked = 0
foreach ($sp in $spans) {
    $s = $sp[0]; $e = $sp[1]
    $diff = $false
    for ($k = $s; $k -lt $e; $k++) { if ($a[$k] -ne $b[$k]) { $diff = $true; break } }
    if (-not $diff) { continue }
    $checked++

    try {
        # 中文比英文宽，译文可能比原串长，所以往后找到真正的 00 为止（不看原串长度）
        $ze = $s
        while ($ze -lt $RdataEnd -and $b[$ze] -ne 0) { $ze++ }
        $str = $utf8Strict.GetString($b, $s, $ze - $s)
    }
    catch { $noise += ('0x{0:X} 不是合法 UTF-8（多半写到一半被截断）' -f $s); continue }

    foreach ($ch in $str.ToCharArray()) {
        $cp = [int][char]$ch
        $ok = ($cp -ge 0x20 -and $cp -le 0x7E) -or
              ($cp -ge 0x3000 -and $cp -le 0x303F) -or
              ($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or
              ($cp -ge 0xFF00 -and $cp -le 0xFFEF) -or
              ($cp -eq 0x00B7) -or ($cp -ge 0x2018 -and $cp -le 0x201D) -or ($cp -eq 0x2026)
        if (-not $ok) {
            $noise += ('0x{0:X} 含异常字符 U+{1:X4}「{2}」' -f $s, $cp, $ch)
            break
        }
    }
}

Write-Host "长度        : $($a.Length) 字节（一致）"
Write-Host "改动段      : $runs"
Write-Host "改动字节    : $bytesChanged"
Write-Host ".rdata 外改动: $outsideRdata"
Write-Host "串区间外改动: $outsideString"
Write-Host "译文检查    : 已改串 $checked 条，异常 $($noise.Count) 条"
if ($runs -eq 0) { Write-Host '两份文件完全相同，没有写入任何译文。' }

if ($outsideRdata -eq 0 -and $outsideString -eq 0 -and $noise.Count -eq 0) {
    Write-Host '结果：PASS（改动都在字符串内部，译文均为合法中文）'
    exit 0
} else {
    Write-Host '结果：FAIL'
    ($bad + $noise) | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    exit 1
}
