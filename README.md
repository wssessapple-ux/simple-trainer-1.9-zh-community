# Simple Trainer 1.9 非官方简体汉化

给 **Simple Trainer for GTA V 1.9（2015 年 7 月版，by Sjaak327）** 做的简体中文菜单汉化。

仓库里**不含**修改过的 `TrainerV.asi`，只有偏移表、打补丁脚本和校验脚本。你需要自备原版文件，脚本在本地完成替换。

## 适用范围

| 项 | 值 |
|---|---|
| 修改器版本 | Simple Trainer 1.9（`Simple Trainer for GTAV Version 1.9` / `July 2015`） |
| 游戏版本 | 1.0.463.1（老版本 GTA V） |
| 原文件大小 | 2,607,616 字节 |
| 原文件 MD5 | `D50B44280A0602ACB9204434A06EA701` |
| 改动范围 | 只改 `.rdata` 里的界面字符串，不动代码段 |

大小或 MD5 不匹配时脚本会直接中止。这不是洁癖——偏移一旦错位，写进去的不是文字而是别的常量。

## 用法

```powershell
# 1. 备份原版
Copy-Item .\TrainerV.asi .\TrainerV.asi.orig

# 2. 打补丁
pwsh -File .\apply.ps1 -Source .\TrainerV.asi.orig -Output .\TrainerV.zh.asi

# 3. 校验，应输出 PASS
pwsh -File .\verify.ps1 -Original .\TrainerV.asi.orig -Patched .\TrainerV.zh.asi

# 4. 覆盖进游戏目录，进故事模式
Copy-Item .\TrainerV.zh.asi 'D:\Games\Grand Theft Auto V\TrainerV.asi'
```

需要对应 1.0.463 的旧版 ScriptHookV 才能加载。

## 原理

`TrainerV.asi` 的 `.rdata` 里界面文案是紧贴排列的 ASCII 串，每条只跟一个 `\0`，之后是 00 填充直到下一条串。菜单项由 8 字节指针数组索引（根菜单数组在文件偏移 `0x20F640`，12 项），所以**只换文字、不改长度结构**就能安全替换。

`apply.ps1` 三步：

1. 按 `dict/zh.tsv` 给的**文件偏移**逐条定位，先核对该偏移处确实是预期的英文原文（不符就报错，不硬写）；
2. 用「到下一个非零字节的距离 − 1」算这条串的真实可用预算，**译文超出就跳过并列出**，绝不越界（越界会吃掉相邻常量，症状是菜单看着正常但逻辑发疯，或直接崩）；
3. 写 UTF-8 字节，剩余空间补 `00`。

`verify.ps1` 反向校验：逐字节比对原版与补丁，确认所有改动段都落在原字符串区间内、`.rdata` 之外零改动。本仓库当前产物自检输出：

```
长度        : 2607616 字节（一致）
改动段      : 1972
改动字节    : 27393
.rdata 外改动: 0
串区间外改动: 0
结果：PASS（全部改动都在字符串内部）
```

## 字形说明（为什么用繁体码位）

游戏自带 `MHeiHK-Bold` 只有繁体字形，写简体码位会显示成方块。所以译文用的是**繁体码位、简体用词**（`載具選項`、`顯示座標`、`無限彈藥`），实际渲染出来能在简体环境下正常显示，大陆玩家也读得懂。

`Options` 那条没翻，原因见下。

## 覆盖率

`report/coverage.csv`：`Off / Len / Budget / Text / Zh / Status`，共 **1942** 条。

覆盖了：根菜单 12 条、Options 两个页面、Weapons 两个页面、载具全部子菜单（改装/颜色/轮胎/车门车窗/灯）、保镖与路人生成、模型与物件生成、传送（地点名、公寓楼层、收藏品）、时间与天气、场景动作、衣服外观、武器配件、状态提示。

**故意保留英文的**：车名/人物/室内模型 ID（`adder`、`patricia`、`wardrobe2` 这类），既翻不出能认的名字，也会和「按模型名生成」的输入框对不上。

## 已知禁改串

`dict/protected.txt`，目前一条：

- `Options`（`0x208808`，RVA `0x209408`）——根菜单设置入口，同时被「编辑车牌」共用，改短会「加载故事模式崩溃」，已复现两次。永久英文。

新增禁改项请写进这个文件，并附崩溃现象（哪个页面、什么时候崩），别只写结论。

## 一个容易踩的坑

短串不要用「子串替换」的思路翻译。`Vehicle Options` 和 `Vehicle Options Menu 1` 是两条不同的串，子串匹配会把 `Vehicle Options Menu 2/3` 一起打坏；同理 `Never Wanted`。

## 贡献

- 补漏译：`dict/zh.tsv` 一行一条，`0x偏移 \t 英文原文 \t 中文`，跑 `apply.ps1` + `verify.ps1`，PASS 且无「原文不符」再提 PR
- 预算先看 `report/coverage.csv` 的 `Budget` 列，UTF-8 一个汉字 3 字节，超了脚本会跳过并列出
- 改完请把 `report/coverage.csv` 一起更新，方便别人看差额

## 免责

- 单机自用。**别在 GTA Online 用**——带 ScriptHookV 上线本身违反 Rockstar 服务条款，跟汉化无关。
- 本项目与 Sjaak327、Rockstar Games 无关联，未获授权或背书。
- 汉化属于对第三方成品的修改，风险自负；发版请只发本仓库的脚本与偏移表，不要分发改过的 `.asi`。

## License

MIT（见 `LICENSE`），仅覆盖本仓库的脚本、偏移表和报告，不涉及 Simple Trainer、GTA V 及其素材的任何权利。
