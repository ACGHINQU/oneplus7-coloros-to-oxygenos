# 文件来源与验证

原始 URL、文件大小和哈希保存在 [artifacts.json](../data/artifacts.json)。已验证的固件分片、更新 APK 及 ADB/Fastboot 组件另保存在 [GitHub Releases](https://github.com/ACGHINQU/oneplus7-coloros-to-oxygenos/releases/tag/assets-2026-09-16)，归档恢复方法见 [archive.md](archive.md)。从设备提取的应用本体、私人调试数据和完整 Google SDK 包没有公开上传。

## 固件

固件来自一加回退资源，源文件名为：

```text
OnePlus7Oxygen_14.P.41_OTA_0410_all_2112101753_downgrade_da90e698650240ff.zip
```

候选包不仅按文件名识别，还核对了包内设备、Android 版本、回退和清除数据标志。文件 MD5 与下载源元数据匹配，并计算 SHA256；这些可以检测文件变化，但仅有哈希并不能独立证明发布者身份。

操作时从手机 `/system/etc/security/otacerts.zip` 取得其信任的 OTA 公钥，确认其证书与包内证书一致，并验证覆盖整个 OTA 签名范围的 RSA 签名。

原检查结果见 [firmware-verification.json](../data/firmware-verification.json)：

- `FullOtaSignatureVerified: true`
- `SignerMatchesDeviceTrustedKey: true`
- 签名覆盖 2,579,321,946 字节。
- 签名摘要算法 OID 为 `1.3.14.3.2.26`（SHA-1），这是历史固件本身使用的格式；额外提供 SHA256 用于当前文件比对。

仓库附带的 [公开证书](../data/oneplus-ota-certificate.pem)是当时比对到的 OnePlus OTA 证书，不是设备私钥。证书 SHA256 为：

```text
4681AD50CAFC580EDFE027BD3FE593254E72CD2DEF1B351FEA306CCF6220CF07
```

`scripts/Verify-OtaSignature.ps1` 是整理仓库时根据上述验证过程编写并在原文件上重新运行的可复现版本；不是声称当时已经保存了同名脚本。它检查 ZIP/Android 签名尾部、签名者公钥、无签名属性的预期结构和实际 RSA 签名，遇到不支持的格式会失败。脚本输出的 `SignatureVerified` 只表示对这份固定公钥验证通过；它不会证明任意另一台手机也信任该公钥或允许回退。

## 独立更新工具 APK

官方旧地址是 `https://oxygenos.oneplus.net/OPLocalUpdate_For_Android12.apk`，本次访问返回 HTTP 403。实际取得文件的社区副本地址记录在清单中。社区副本不自动具有官方可信度，因此进行了额外验证。

操作时从当前手机提取原有官方系统更新应用 `/system/system_ext/app/OTA/OTA.apk`，比对证书，并验证副本的 APK v1 签名、完整清单哈希与全部 1196 个签名条目。没有将“只看证书名字”当成完整验证。

两个 APK 的证书 SHA256 相同：

```text
FC98DAE63AD39626C8C67FBE83F2F06F74932A9CD146B92CECFC6A047A904386
```

原检查结果见 [updater-apk-verification.json](../data/updater-apk-verification.json)。APK 在手机安装时还须经过 Android 自己的安装验证。

仓库中的 `Verify-Artifacts.ps1` 只复核本案例已验证 APK 的大小与 SHA256，没有重新实现 APK/JAR 签名验证。原始完整验证结果与后续哈希复核在证据中分开保留。

## 来源的稳定性

- 固件使用精确文件名和 SHA256 固定本次文件，旧 URL 的可用性可能变化。
- 社区 APK 链接指向仓库分支，内容也可能变化；以清单中的 SHA256 判定是否仍是本次验证的文件。
- 下载到不同哈希的文件时不能继续把本案例的验证结论套在该文件上。
- 为减少旧链接失效的影响，增加了独立 Release 归档。固件分片合并后的 SHA256 与原包完全相同，完整 OTA 签名再次验证通过；结果见 [release-archive-validation.json](../data/release-archive-validation.json)。
- 资源列表：[Oxygen Updater](https://oxygenupdater.com/article/352/)。机制说明：[Android OTA 签名文档](https://source.android.com/docs/core/ota/sign_builds)。
