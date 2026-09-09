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


## 构建 5：记账语义与外观变体

使用内置 imagegen 分别编辑三个资源，随后等比例转换为 1024×1024。原纸纹未更换。

- 浅色：`MoneyNote/Assets.xcassets/AppIcon.appiconset/icon.png`
- 深色：`MoneyNote/Assets.xcassets/AppIcon.appiconset/icon-dark.png`
- 着色：`MoneyNote/Assets.xcassets/AppIcon.appiconset/icon-tinted.png`

浅色编辑提示词：

Use case: precise-object-edit. Asset: 1024x1024 iOS app icon for Chinese personal bookkeeping app 轻账记. Edit target is the supplied current icon. Keep its centered black rounded notebook silhouette, spine, generous margins, warm ivory paper background and quiet tactile character. Refine ONLY the interior mark: replace the large checkmark with a clean modest yen/yuan ¥ symbol, centered on the lower ledger page; retain two short horizontal ledger lines above it. Make linework crisp, deliberate, legible at small size. Reduce paper grain and creasing inside the black ink so it reads pure black; keep subtle warm paper texture outside. No green or other accent color. Full-bleed square, no rounded external corners baked in, no outer border, no drop shadow, no extra text or logos. Production icon, not mockup.

深色提示词：

Use case: precise-object-edit. Make the dark appearance variant of this exact iOS bookkeeping icon. Preserve EXACT notebook outline, spine, two lines and yuan ¥ mark geometry, position, proportions and generous margins. Change colors only. Full-bleed neutral charcoal #202020 paper background with almost imperceptible matte texture, icon strokes warm off-white #F3F0E8, entirely monochrome. 1024x1024 square. No built-in rounded outer corners, no shadow, no outer border, no text, no green, no added shapes.

着色提示词：

Use case: precise-object-edit. Make the tinted appearance variant of this exact iOS bookkeeping icon. Preserve EXACT notebook outline, spine, two lines and yuan ¥ mark geometry, position, proportions and generous margins. Change colors only. Full-bleed solid pure black background, all notebook and yuan strokes flat pure white, interior same pure black background. No paper grain or gradients. This is a grayscale source for iOS tinted icon rendering. 1024x1024 square. No built-in rounded outer corners, no shadow, no outer border, no text, no green, no added shapes.
