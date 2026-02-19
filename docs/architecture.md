# AI-Local-Sandbox 架构设计文档

## 1. 项目定位

本项目是一个 **纯本地运行** 的多模态 AI 交互平台，面向消费级 GPU（12GB VRAM）设计。
核心目标：在单张 GPU 上同时支持文本对话、图像理解、语音交互、图像生成，无需外部 API。

## 2. 系统架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                        Gradio Web UI (:7860)                    │
│  ┌──────────┐  ┌──────────────┐  ┌───────────┐  ┌───────────┐  │
│  │ minicpm  │  │ webcam_live  │  │ sdxl_safe  │  │   sdxl    │  │
│  │  .py     │  │ _gradio.py   │  │   .py      │  │   .py     │  │
│  └────┬─────┘  └──────┬───────┘  └─────┬─────┘  └─────┬─────┘  │
└───────┼────────────────┼────────────────┼──────────────┼────────┘
        │                │                │              │
        ▼                ▼                ▼              ▼
┌───────────────┐ ┌─────────────┐ ┌──────────────────────────────┐
│  MiniCPM-V    │ │ MiniCPM-V   │ │   Stable Diffusion Pipelines │
│  4.5-int4     │ │ 4.5-int4    │ │  ┌─────────┐ ┌───────────┐  │
│  (GPU, fp16)  │ │ (GPU, fp16) │ │  │ sd-turbo│ │sdxl-turbo │  │
│               │ │             │ │  └─────────┘ └───────────┘  │
│  + Whisper    │ │             │ │  ┌─────────────────────────┐ │
│  (CPU, int8)  │ │             │ │  │ sdxl-base-1.0 (normal) │ │
│               │ │             │ │  └─────────────────────────┘ │
│  + Piper TTS  │ │             │ │  + ControlNet (canny SDXL)  │
│  (CPU, ONNX)  │ │             │ │                              │
└───────────────┘ └─────────────┘ └──────────────────────────────┘
```

## 3. VRAM 管理策略

核心设计决策：**CPU ↔ GPU 乒乓调度**

```
Pipeline 加载 → CPU (torch.float16)
    ↓ 推理请求到达
    ↓ pipe.to("cuda")
    ↓ torch.inference_mode()
    ↓ 推理完成
    ↓ pipe.to("cpu")
    ↓ torch.cuda.empty_cache()
```

所有 SD pipeline 默认驻留 CPU，仅在推理时短暂移至 GPU，推理完立即释放。
MiniCPM 通过 `device_map="auto"` 常驻 GPU（INT4 量化，约 4-5GB）。

辅助 VRAM 优化手段（在 `_configure_pipe()` 中统一配置）：
- `enable_attention_slicing()`
- `enable_vae_slicing()`
- `enable_xformers_memory_efficient_attention()`（可选）

## 4. 模块职责

| 文件 | 职责 | GPU 使用 |
|------|------|----------|
| `minicpm.py` | 主应用：多模态聊天 + 语音 + 图生 | MiniCPM 常驻 GPU; SD 按需上 GPU |
| `webcam_live_gradio.py` | 实时摄像头视觉分析 | MiniCPM 常驻 GPU |
| `sdxl_safe.py` | 安全参数的图像生成（Draft + Refine） | SD 按需上 GPU |
| `sdxl_safe_canny.py` | 带 Canny ControlNet 的图像生成 | SD + ControlNet 按需上 GPU |
| `sdxl.py` | 自由参数的图像生成（高级用户） | SD 按需上 GPU |

## 5. 环境变量

| 变量 | 默认值 | 作用 |
|------|--------|------|
| `PYTORCH_CUDA_ALLOC_CONF` | `expandable_segments:True` | 减轻 CUDA 内存碎片 |
| `MODEL_ID` | `openbmb/MiniCPM-V-4_5-int4` | webcam 模块的模型路径 |

## 6. 依赖架构

```
transformers==4.51.0   ← MiniCPM trust_remote_code 兼容性锁定
accelerate==1.12.0     ← device_map="auto" 支持
diffusers==0.36.0      ← SD / ControlNet pipeline
gradio==6.5.1          ← Web UI
faster-whisper==1.2.1  ← CPU 语音识别
piper-tts==1.4.1       ← CPU 离线 TTS
bitsandbytes==0.49.1   ← INT4 量化支持
```
