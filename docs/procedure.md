# 完整操作过程

本文记录 2026-09-16 的一次实际操作。**回退包会清除全部手机数据。** 本次在机主明确确认备份完成或无需保留数据、同意清空后才进入安装步骤。以下命令展示当时做过的动作，不是要求读者不加判断地逐条执行的批处理脚本。

## 1. 确认型号与连接

Windows 电脑使用 Google 官方 Platform Tools 37.0.1-15733141。手机最初已连接 USB，并处于 Fastboot 模式。Windows 驱动能正常工作。

```powershell
fastboot devices
fastboot -s '<DEVICE_SERIAL>' getvar product
fastboot -s '<DEVICE_SERIAL>' getvar unlocked
fastboot -s '<DEVICE_SERIAL>' oem device-info
fastboot -s '<DEVICE_SERIAL>' flashing get_unlock_ability
```

观察到 `product: msmnile`、`unlocked: no`、`Device unlocked: false`、`get_unlock_ability: 1`。`msmnile` 是平台信息，不能单独用于区分一加 7 和其他同平台机型。

之后正常启动系统，通过已授权的 ADB 确认型号 **GM1900**、设备 **OnePlus7**、项目 **18857**；原系统为 **GM1900_11_H.40 / Android 12 / ColorOS 12.1**。完整构建信息见 [设备输出](../data/android-device-info.txt)。

## 2. 实际尝试标准解锁并记录失败

当时分别执行过下面两条命令；这是失败分支的记录，后续成功安装并不要求再次运行它们。

```powershell
fastboot -s '<DEVICE_SERIAL>' oem unlock
fastboot -s '<DEVICE_SERIAL>' flashing unlock
```

两次输出均为：

```text
FAILED (remote: 'Device cannot be unlocked for technical reason.')
fastboot: error: Command failed
```

通信正常、OEM 解锁许可已开启，而手机端仍拒绝命令。因此没有继续重复安装驱动或反复发送相同命令。这条错误没有提供足够信息来确定底层拒绝原因。

原计划改为先回退 Android 11，再尝试解锁。本次没有进入 9008 模式。

## 3. 获取匹配的回退包并验证

从 [Oxygen Updater 的回退列表](https://oxygenupdater.com/article/352/)定位 **OnePlus 7 Global/India** 包，目标 OxygenOS 11.0.5.1 / Android 11。这个列表来自 Oxygen Updater 项目维护者；固件链接指向一加资源。不能混用 OnePlus 7 Pro、7T、7T Pro 的文件。

```text
OnePlus7Oxygen_14.P.41_OTA_0410_all_2112101753_downgrade_da90e698650240ff.zip
```

旧域名连接不可用时，从对应 S3 资源取得文件。检查包内 `pre-device=OnePlus7`、`ota-downgrade=yes`、`ota-wipe=yes`，核对文件大小和哈希，再用从当前手机 `/system/etc/security/otacerts.zip` 提取的信任公钥验证完整 OTA 签名。

数据源和检查方法见 [验证说明](verification.md)，原始元数据见 [ota-metadata.txt](../data/ota-metadata.txt)。这里的 `ota_version` 含有兼容性字段；目标系统识别同时依据 `post-build`、Android SDK 等字段和发布说明，不能仅凭某一个文件名片段判断。

## 4. 原更新入口失败，改用独立官方更新工具

先在 ColorOS“关于本机 → 系统更新 → 本地安装”中选择固件，界面显示“验证失败”，安装未开始。保存的日志没有给出足以确认原因的信息；不能据此断言一定是地区限制、版本限制或文件损坏。

接着取得独立工具 `OPLocalUpdate_For_Android12.apk`。旧 APK 官方下载入口返回 HTTP 403，因此使用社区保存的副本。安装前验证其签名、完整清单和 1196 个签名保护的条目；其签名证书与当前手机官方系统更新应用的证书相同。工具包名为 `com.oneplus.opbackup`，观察到的版本为 `1.0.0-S-DP`。

```powershell
adb -s '<DEVICE_SERIAL>' install 'OPLocalUpdate_For_Android12.apk'
```

手机出现安装确认时在界面完成确认。没有禁用系统签名校验。这个独立工具成功接受了同一个回退包。

## 5. 传输、选择回退包并安装

将文件置于手机内部存储根目录，保持原文件完整：

```powershell
adb -s '<DEVICE_SERIAL>' push `
  'OnePlus7Oxygen_14.P.41_OTA_0410_all_2112101753_downgrade_da90e698650240ff.zip' `
  '/sdcard/'
```

传输完成后文件大小为 **2,579,323,479 字节**。在独立“系统更新”工具内选择“本地升级”，选中这个包。

工具提示安装将格式化手机，按机主已给出的授权确认。随后系统要求验证锁屏密码，由机主直接在手机上输入。密码没有交给电脑端记录或写入聊天。

界面操作根据实时读取的 UI 元素进行。屏幕坐标会受分辨率和界面状态影响，因此本项目没有将当时的点击坐标写成自动刷机脚本。

## 6. 等待安装结束并重启

实际观察到进度 9%、48%、71%、84%、100%。只有工具明确显示“安装完成，重启手机开始体验吧！”并给出“重启手机”按钮后，才通过该按钮重启。

重启时 ADB 连接断开；机主先报告开机动画/清除数据，后来确认国际版系统已经安装成功，并说明换国际版就是主要目的。手机随后断开电脑，操作结束。

最初计划中的“回退后再解锁”没有执行。这个案例只能证明本机在上述条件下成功完成了官方回退安装，不能作为“bootloader 已解锁”的证据。
