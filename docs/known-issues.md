# 已知限制与改进方向

## 1. 当前限制

### 1.1 VRAM 约束
- 同时运行 MiniCPM + SDXL Normal 可能导致 OOM（12GB 边界情况）
- 建议不要在 minicpm.py 中同时触发图像生成和复杂对话

### 1.2 代码层面
- `minicpm.py` 存在重复 import（`hashlib`, `dataclass`, `OrderedDict` 各导入两次）
- `webcam_live_gradio.py` 调用了两次 `demo.launch()`（第二次覆盖第一次）
- TTS WAV 文件写入 `/tmp`，未做定期清理
- 无 Makefile，缺少标准化的 build/test/lint 入口

### 1.3 安全性
- `trust_remote_code=True` 存在远程代码执行风险（HuggingFace 模型）
- Gradio 默认监听 `0.0.0.0`，生产环境需要加认证

### 1.4 可观测性
- 无结构化日志（仅 print）
- 无 metrics endpoint
- 无 health check

## 2. 改进方向

| 优先级 | 改进项 |
|--------|--------|
| P0 | 添加 Makefile（lint, test, run targets） |
| P0 | 修复 webcam 双 launch、重复 import |
| P1 | 添加 `/tmp` TTS 文件清理机制 |
| P1 | 结构化日志（logging 模块） |
| P2 | 抽取公共 SD pipeline 管理为独立模块 |
| P2 | 添加 `--model` CLI 参数替代硬编码 |
| P3 | 添加 Docker/Containerfile |
| P3 | GPU 内存监控面板（nvidia-smi 集成） |
