# 安装文件归档与恢复

**[打开本次实测文件的 Release 下载页](https://github.com/ACGHINQU/oneplus7-coloros-to-oxygenos/releases/tag/assets-2026-09-16)**

官方旧固件入口在本次操作时无法连接，原本地更新 APK 下载入口返回 HTTP 403。原始链接、版本号和哈希都值得保留，但链接本身不能保证文件以后仍可取得，因此增加这份独立文件归档。

## 归档内容

| 文件 | 用途 |
| --- | --- |
| `OnePlus7Oxygen_…zip.part001` | 固件前 1,610,612,736 字节（1.5 GiB） |
| `OnePlus7Oxygen_…zip.part002` | 固件剩余 968,710,743 字节 |
| `OPLocalUpdate_For_Android12.apk` | 本次验证并成功使用的一加独立本地更新工具，原文件不变 |
| `adb-fastboot-windows-37.0.1-case-tools.zip` | 本次使用的 Windows ADB、Fastboot、所需 DLL、原 NOTICE 与版本信息 |
| `archive-manifest.json` | 分片、完整固件、APK 和工具文件的精确大小与 SHA256 |
| `Restore-Firmware.ps1` | 在电脑上校验分片并恢复原固件，不连接或操作手机 |
| `SHA256SUMS.txt` | Release 下载附件的 SHA256 列表 |
| `ARCHIVE-README.md` | 可随附件保存的离线使用说明 |

GitHub [每个 Release 附件须小于 2 GiB](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)。原固件为 2,579,323,479 字节，所以按原始字节切成两份；没有重新压缩固件、修改 ZIP 内部内容或更改 OTA 签名。

## 下载并恢复完整固件

1. 从 Release 下载两个以 `.part001`、`.part002` 结尾的固件文件，以及 `archive-manifest.json` 和 `Restore-Firmware.ps1`，放入同一个文件夹。
2. 使用 PowerShell 7 打开该文件夹。至少再预留约 2.6 GB 空间来生成完整 ZIP。
3. 执行：

```powershell
pwsh -File .\Restore-Firmware.ps1 -PartsDirectory .
```

脚本先检查每个分片的大小和 SHA256，再合并，最后检查完整文件的固定 SHA256。成功时输出 `RestoredExactly: true`，生成：

```text
OnePlus7Oxygen_14.P.41_OTA_0410_all_2112101753_downgrade_da90e698650240ff.zip
```

如果目标 ZIP 已经存在且校验正确，脚本直接报告它已存在；如果同名文件内容不同，则停止，不覆盖已有文件。分片缺失或损坏也会停止。

**手机本地更新工具需要的是恢复后的完整 ZIP。不要选择 `.part001`、`.part002`，也不要解压后重新打包固件。** 后续安装过程见 [操作记录](procedure.md)，其中包含清空数据步骤。

完整 ZIP 的 SHA256：

```text
E15EE75F64CF6E19AE7696A0C933C5AA3B811850A0BC67407CB2D669DC74C19E
```

本地实测已将两份分片重新合并，确认与原 ZIP 完全一致，并重新验证了整个 OTA 签名。还测试了错误分片校验值会被拒绝。记录在 [归档验证结果](../data/release-archive-validation.json)。

## APK 与 Windows 工具

更新工具 APK 是原先验证过的同一文件，SHA256 不变：

```text
57751A3B0F5F1727A3C46641294FDDF3E06588FD1C86BF47DEE9D7560A81001C
```

Windows 工具 ZIP 是本项目从实测 Platform Tools 37.0.1 中整理的组件集合，**不是 Google 发布的完整 SDK 压缩包**。其中的 `adb.exe`、`fastboot.exe` 与 DLL 未修改，原 `NOTICE.txt` 和 `source.properties` 原样保留。逐文件校验值在归档清单中；独立解压后已验证 ADB/Fastboot 能显示 `37.0.1-15733141`。

这些开源组件的代码来源包括 [ADB](https://android.googlesource.com/platform/packages/modules/adb/) 和 [Fastboot](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fastboot/)，各组件适用其原有许可和声明。原固件及 APK 的权利归 OnePlus/OPPO 及相应权利人；本项目没有为第三方文件重新许可，也未将其标成自己开发的软件。

该工具包没有驱动安装程序。本次电脑的 Android 驱动原本可用；若另一台电脑不识别设备，仍需配置合适的 USB 驱动。

## 如何重建归档

在完整仓库中，具备原固件、APK 和实测 Platform Tools 目录后，可以运行：

```powershell
pwsh -File scripts/New-ReleaseArchive.ps1 `
  -FirmwarePath 'D:\Downloads\OnePlus7Oxygen_14.P.41_OTA_0410_all_2112101753_downgrade_da90e698650240ff.zip' `
  -UpdaterApkPath 'D:\Downloads\OPLocalUpdate_For_Android12.apk' `
  -PlatformToolsDirectory 'D:\Downloads\platform-tools' `
  -OutputDirectory 'D:\Downloads\oneplus7-archive'
```

输出目录必须尚不存在。固件和 APK 在生成归档前先与本案例清单核对。固件分片是确定的原始字节范围；重新生成的工具 ZIP 可能因 ZIP 元数据产生不同压缩包哈希，需以生成时的清单为准并核对内部成员与原文件一致。

文件归档保存的是这次实测版本，并不代表厂商仍在为其提供更新。GitHub Release 也不是永久保存承诺；保留一份自己可控制的离线副本仍然有价值。
