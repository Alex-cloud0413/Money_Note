# 纸质视觉素材

素材由内置 imagegen 生成，已作为本工程的真实资源保存。图标转换到 iOS 要求的 1024×1024 像素；纸纹按浅色/深色不同透明度显示，增强对比度时隐藏。

- App 图标：`MoneyNote/Assets.xcassets/AppIcon.appiconset/icon.png`
- 纸纹：`MoneyNote/Assets.xcassets/PaperTexture.imageset/paper.png`
- 颜色、字体层级、卡片与分类图标：`MoneyNote/PaperTheme.swift`

## 图标生成提示词

Create a production iOS app icon for a refined Chinese personal bookkeeping app called 轻账记. Square 1024x1024 bitmap, fully opaque full bleed background, NO rounded outer frame (iOS masks it). Warm ivory archival cotton paper texture with very subtle gentle creases, premium quiet stationery design. One central very simple elegant dark charcoal-green line symbol of a closed ledger notebook, a fine vertical spine and two minimal horizontal entry lines; an understated diagonal rising check stroke integrated into lower right of notebook. Symbol bold enough to be unmistakable at 60 pixels but balanced, lots of breathing room. Minimal ink palette charcoal #303D35 and muted sage on warm offwhite #F3F0E7. Refined printed/very shallow deboss finish, flat front on composition, no perspective, NO money symbols, NO coins, NO charts, NO colorful emojis, NO letters, NO text, NO border, NO mockup device, NO glossy 3D. This is a standalone replacement app icon asset, not a presentation.

## 纸纹生成提示词

A seamless-looking quiet warm ivory cotton paper surface to use as a premium bookkeeping iPhone app's full screen background, portrait 2:3. Photographic macro material texture only, evenly softly lit, extremely restrained fine natural fibers and a few barely perceptible soft shallow irregular crumples as though gently smoothed handmade paper. Mostly flat cream offwhite #F3F0E8, low contrast, no large diagonal bands, no distinct crease lines, no strong shadows, no torn edges, no objects, no icons, no text, no vignette, no dirty spots. Texture should stay gentle behind highly legible small dark text. Fill entire image with paper at uniform scale.


## 构建 4：黑色调整

界面主文字和强调色使用 #000000，图表采用中性灰阶。暖白纸纹保持原样；深色模式使用中性深灰背景和白色前景。图标仍使用内置 imagegen 做局部颜色编辑，输出保存在原 AppIcon 资源路径。

编辑提示词：Edit this existing app icon with exactly one change: convert ALL green / green-gray ink of the notebook outline, spine, entry lines and checkmark to pure neutral black ink (#000000, with only neutral gray where the existing printed paper texture softly modulates it). Preserve the icon geometry, stroke widths, placement, proportions, scale, spacing, softly wrinkled warm ivory paper background and all texture exactly. Keep the warm ivory paper color unchanged. No green tint anywhere in the symbol. No new text, no additional objects, no outer rounded mask. Same square full-bleed opaque iOS icon composition, ready as a 1024x1024 asset.
