# FocusMic 直发版发布流程

这个流程用于 GitHub Release + Sparkle appcast 的直发版，不用于 App Store 版。

## 前置条件

- 本机已登录 GitHub CLI：`gh auth status`。
- Xcode 可以 archive `FocusMic` scheme。
- `SupportFiles/FocusMic-Info.plist` 已配置 `SUPublicEDKey`。
- Sparkle 私钥在本机 Keychain 中，`sign_update` 能直接签名。
- 正式发布建议准备 Developer ID 证书和 notarization profile。

notarization profile 只需要配置一次：

```sh
xcrun notarytool store-credentials focusmic-notary \
  --apple-id "你的 Apple ID" \
  --team-id "你的 Team ID" \
  --password "app-specific password"
```

## 默认准备发布材料

```sh
scripts/release-direct.sh 0.0.2 6
```

脚本会完成：

- 更新直发版 target 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`；
- archive/export `FocusMic.app`；
- 压缩为 `build/releases/v0.0.2/FocusMic-0.0.2.zip`；
- 使用 Sparkle `sign_update` 生成 `sparkle:edSignature` 和 `length`；
- 在 `landing/appcast.xml` 顶部追加新版本 `<item>`。

默认不会 commit、tag、push，也不会创建 GitHub Release。

## 推荐正式发布

先确保当前分支已经干净，并且所有功能改动已经提交。然后运行：

```sh
NOTARYTOOL_PROFILE=focusmic-notary scripts/release-direct.sh 0.0.2 6 --ship --notarize
```

`--ship` 会在准备发布材料之后继续执行：

- commit `FocusMic.xcodeproj/project.pbxproj` 和 `landing/appcast.xml`；
- 创建 annotated tag，例如 `v0.0.2`；
- push 当前分支和 tag；
- 创建 GitHub draft release，并上传 zip。

确认 GitHub 草稿 Release 和官网 appcast 部署都没问题后，再在 GitHub 上发布草稿。

如果要直接发布为公开 Release：

```sh
NOTARYTOOL_PROFILE=focusmic-notary scripts/release-direct.sh 0.0.2 6 --ship --publish --notarize
```

## 常用参数

```sh
TEAM_ID=C6H9D46LA6 scripts/release-direct.sh 0.0.2 6 --ship
SPARKLE_BIN=/path/to/Sparkle/bin scripts/release-direct.sh 0.0.2 6
scripts/release-direct.sh 0.0.2 6 --overwrite
scripts/release-direct.sh 0.0.2 6 --allow-dirty
```

- `TEAM_ID`：传给 `xcodebuild -exportArchive` 的 Apple team ID。
- `SPARKLE_BIN`：当脚本找不到 Sparkle 工具时，手动指定包含 `sign_update` 的目录。
- `--overwrite`：删除并重建同版本的 `build/releases/v版本号` 输出目录。
- `--allow-dirty`：只适合 prepare 阶段，不能和 `--ship` 一起使用。

## 每次更新版本要做什么

1. 把功能改动提交干净。
2. 决定新的用户版本号和 build 号，例如 `0.0.3 7`。
3. 运行 `scripts/release-direct.sh 0.0.3 7 --ship --notarize`。
4. 检查 GitHub draft release 的 zip、签名和说明。
5. 确认 `landing/appcast.xml` 已推送到 `main`，并可通过 `https://raw.githubusercontent.com/lageev/FocusMic/main/landing/appcast.xml` 访问。
6. 发布 GitHub Release。
