# 已知限制与改进方向

## 1. 当前限制

### 1.1 GGUF 模式下视觉/图片功能不可用

**状态**: 已做优雅降级，等待上游修复

**现象**:
用户在 `minicpm-o.py`（GGUF 入口）上传图片时，程序崩溃（core dump）。

**根因分析**:

llama-cpp-python 0.3.16（截至 2026-02 的最新版）不支持 MiniCPM-o 4.5 的视觉编码器。
GGUF 视觉模型文件 `MiniCPM-o-4_5-vision-F16.gguf` 的元数据标记为 `minicpmv_version=100045`，
而 llama-cpp-python 内嵌的 llama.cpp 仅支持 MiniCPM-V 2.6。

两条技术路径均不可行：

| 路径 | 做法 | 失败原因 |
|------|------|---------|
| A: `clip_model_path` 传入 `Llama()` | 期望原生加载视觉编码器 | `Llama.__init__` 无 `clip_model_path` 形参，被 `**kwargs` 静默吞掉。图片以 OpenAI vision list 格式传入后，GGUF 内嵌的 Jinja2 chat template 对 list 调用 `.startswith()` 崩溃：`jinja2.exceptions.UndefinedError: 'list object' has no attribute 'startswith'` |
| B: `MiniCPMv26ChatHandler` | 使用 llama-cpp-python 内置的 MiniCPM 视觉 handler | `mtmd` 库加载视觉模型时断言失败：`GGML_ASSERT(false && "unsupported minicpmv version")` — 因为 handler 只支持 v2.6，不支持 v4.5 (version=100045) |

**当前修复（优雅降级）**:

1. `GGUFMiniCPMModel.__init__` — 不再传入 `clip_model_path` 或 `chat_handler`，标记 `vision_supported = False`
2. `_convert_msgs()` — 遇到 PIL Image 时剥离图片，保持 `content` 为纯字符串
3. `chat_step()` / `chat_step_stream()` — 检测到图片上传时在 UI 显示中文警告：
   > ⚠️ 图片已接收但无法视觉处理 — 当前 GGUF 模式不支持图像识别。仅处理文本内容。
4. 纯文本对话完全不受影响

**后续计划**:
- 持续关注 [llama-cpp-python releases](https://github.com/abetlen/llama-cpp-python/releases)
- 当新版本的 `MiniCPMv26ChatHandler`（或新 handler）支持 `minicpmv_version >= 100045` 时，恢复视觉功能
- 跟踪 issue: llama.cpp `tools/mtmd/mtmd.cpp` 中 `minicpmv_version` 白名单

### 1.2 VRAM 约束
- 同时运行 MiniCPM + SDXL Normal 可能导致 OOM（12GB 边界情况）
- 建议不要在 minicpm.py 中同时触发图像生成和复杂对话

### 1.3 代码层面
- `minicpm.py` 存在重复 import（`hashlib`, `dataclass`, `OrderedDict` 各导入两次）
- `webcam_live_gradio.py` 调用了两次 `demo.launch()`（第二次覆盖第一次）
- TTS WAV 文件写入 `/tmp`，未做定期清理

### 1.4 安全性
- `trust_remote_code=True` 存在远程代码执行风险（HuggingFace 模型）
- Gradio 默认监听 `0.0.0.0`，生产环境需要加认证

### 1.5 可观测性
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
