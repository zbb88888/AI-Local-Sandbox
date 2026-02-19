# 部署与运行指南

## 1. 支持的运行环境

| 环境 | 状态 |
|------|------|
| Ubuntu 24.04 (Native) | ✅ 推荐 |
| WSL2 (Windows) | ✅ 测试通过 |
| macOS | ❌ 不支持（需要 CUDA） |

## 2. 硬件要求

| 组件 | 最低要求 |
|------|----------|
| GPU | NVIDIA, ≥ 12GB VRAM |
| CUDA | 12.1+ |
| CPU | 支持 Whisper + Piper 推理 |
| RAM | 建议 ≥ 16GB |

## 3. 应用入口与端口

所有应用统一监听 `0.0.0.0:7860`，浏览器访问 `http://localhost:7860`。

| 命令 | 功能 |
|------|------|
| `python minicpm.py` | 多模态聊天（主应用） |
| `python webcam_live_gradio.py` | 实时摄像头分析 |
| `python sdxl_safe.py` | 安全参数图像生成 |
| `python sdxl_safe_canny.py` | 带 ControlNet 图像生成 |
| `python sdxl.py` | 自由参数图像生成 |

**注意**：同一时间只能运行一个应用（端口冲突 + GPU 共享）。

## 4. 首次运行

首次启动任何脚本时，会自动从 HuggingFace Hub 下载模型权重：

| 模型 | 大小（约） | 用途 |
|------|-----------|------|
| `openbmb/MiniCPM-V-4_5-int4` | ~5GB | 多模态 LLM |
| `stabilityai/sd-turbo` | ~2GB | 快速图生 |
| `stabilityai/sdxl-turbo` | ~6GB | SDXL 快速图生 |
| `stabilityai/stable-diffusion-xl-base-1.0` | ~6GB | 高质量图生 |
| `diffusers/controlnet-canny-sdxl-1.0` | ~2.5GB | Canny ControlNet |
| `faster-whisper` "small" | ~500MB | 语音识别 |

后续启动使用本地缓存（`~/.cache/huggingface/`）。

## 5. Piper TTS 配置

Piper voice 模型需要手动下载：

```
~/piper_voices/libritts_r_medium/
├── en_US-libritts_r-medium.onnx
└── en_US-libritts_r-medium.onnx.json
```

路径硬编码在 `minicpm.py` 的 `PIPER_VOICE` 变量中。
如需更换声音，修改该变量并下载对应的 ONNX 模型。

## 6. WSL2 安装快速路径

```bash
# Windows CMD
wsl --install -d Ubuntu-24.04 --name AI-Sandbox

# WSL Shell
cd ~
git clone https://github.com/amill288/AI-Local-Sandbox.git
cd AI-Local-Sandbox
python3 -m venv .venv && source .venv/bin/activate
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
sudo apt install -y ffmpeg
pip install -r requirements.txt
# + Piper voice 下载（见 README）
```

## 7. 清理重装

```bash
# Windows CMD
wsl --unregister AI-Sandbox
```

然后重新执行安装步骤。

## 8. 依赖锁定

- [requirements.txt](../requirements.txt): 带版本约束的依赖声明
- [requirements.lock.txt](../requirements.lock.txt): 完全锁定的依赖快照（可复现环境）

关键版本锁定原因：
- `transformers==4.51.0`: MiniCPM `trust_remote_code` 兼容性
- `accelerate==1.12.0`: `device_map="auto"` 支持
- `gradio==6.5.1`: UI streaming API 兼容性
- `diffusers==0.36.0`: ControlNet pipeline API 稳定性
