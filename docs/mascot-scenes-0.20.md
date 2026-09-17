# 页面场景素材

使用内置 imagegen，根据用户提供的 E:/blue-note/app吉祥物一览.png 作为角色和画风参考生成，不使用 CLI 或外部付费 API。三张均保留真实 RGBA 透明通道，未覆盖原始参考图。

项目文件：
- assets/brand/mascot-explore.png：小尺使用笔记本电脑探索，旁边地球仪。
- assets/brand/mascot-capture.png：笔记本角色用相机记录数学纸页。
- assets/brand/mascot-messages.png：橡皮与荧光笔交流，配对话气泡。

共同提示：Create one production UI illustration for Blue-note Android app. Reference sheet is character/style reference only. Match soft polished 3D toy style, blue #2878F0 accents. Fully isolated objects on genuine transparent alpha background, no opaque backdrop, no tile, no frame, no text, no checkerboard painted into image, no floor plane. Full silhouettes uncut, centered, tight balanced composition, small outer transparent padding. Save transparent PNG.

独立场景提示：
1. Blue ruler mascot from reference, big friendly eyes and white gloves, browsing a small blue laptop, tiny globe beside laptop. Single compact scene.
2. White spiral notebook mascot from reference, big friendly eyes and white gloves, holding a small blue camera taking a photo of a sheet of math notes. Single compact scene.
3. Pink eraser and yellow highlighter mascots from reference, friendly eyes white gloves, facing each other chatting with two small blue empty speech bubbles overhead. Single compact scene.

已检查生成图像、透明通道和接入位置。文字、按钮、状态信息由 Flutter 绘制，素材仅作引导与空状态陪伴。
