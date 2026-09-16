# 证据及适用范围

## 数据来源

| 文件 | 来源及处理方式 |
| --- | --- |
| `data/android-device-info.txt` | 原 ADB 属性输出；构建指纹是系统版本标识，不是指纹生物信息 |
| `data/fastboot-diagnostics-initial.txt` | 原命令记录；设备序列号替换为 `<DEVICE_SERIAL>` |
| `data/fastboot-unlock-attempt.txt` | 原 `oem unlock` 失败输出 |
| `data/fastboot-flashing-unlock-attempt.txt` | 原 `flashing unlock` 失败输出 |
| `data/fastboot-project-info.txt` | 原辅助查询失败输出；不属于解锁结果 |
| `data/firmware-verification.json` | 操作时保存的完整 OTA 签名及文件校验结果 |
| `data/updater-apk-verification.json` | 操作时保存的 APK 完整签名检查结果 |
| `data/ota-metadata.txt` | 从实际采用的完整固件中提取，保留原字段 |
| `data/oneplus-ota-certificate.pem` | 与原手机信任证书一致的厂商公开 OTA 证书 |
| `data/artifacts.json` | 根据已保存的文件及下载记录整理的资源清单 |
| `data/observations.json` | 根据工具返回和机主回复转录的安装顺序；不是伪造的原始日志 |
| `data/reproduction-validation.json` | 整理仓库时对原文件重新运行公开验证脚本的结果 |
| `data/release-archive.json` | Release 归档分片、APK 与工具组件的名称、大小、SHA256 和下载地址 |
| `data/release-archive-validation.json` | 固件重组、完整 OTA 签名复核、错误校验值拒绝和工具组件核验结果 |

公开文本统一为 LF 换行；原 OTA 元数据中用于对齐的尾部空格保留，因此这些原始文本不按代码格式删除行末空格。

原 Fastboot 诊断记录内的 `ExitCode=0` 来自当时的命令包装记录；其中个别不支持的查询仍显示 `FAILED`。判断这些命令结果以设备输出为准，不能把包装层退出码当作查询成功的证据。

完整 UI XML、Android logcat 和系统应用转储包含与案例无关的设备环境信息，保留在原电脑，不公开上传。安装进度和“验证失败”等界面文字在 `observations.json` 中明确标注为工具输出转录。没有为缺失的原始界面输出补造时间戳或截图。

## 可以确认

- 原手机和系统型号、初始锁定状态、OEM 解锁许可。
- 两条标准解锁命令均失败，拒绝来自手机端。
- 固件适配声明、完整签名验证结果和工具 APK 验证结果。
- ColorOS 内置更新器拒绝了安装；独立一加更新工具接受并显示安装完成。
- 机主在重启后确认已换成国际版系统。

## 未验证或不能据此推出

- bootloader 解锁成功；本案例没有该成功记录。
- 最终精确运行版本和锁定状态；电脑在重启后未再次读取。
- 原始“technical reason”或“验证失败”的底层原因。
- 其他一加 7 构建、7 Pro、7T 或其他型号同样可用。
- 国际版所有功能、运营商兼容性或后续更新行为均已通过测试。

本项目没有私钥、手机序列号、IMEI、账户凭据、密码或个人电脑路径。需要长期保存的安装文件放在独立 Release 中，不写入 Git 历史。原始调试材料与公开摘录分开保存；公开数据没有更改设备错误信息或把失败改写成成功。
