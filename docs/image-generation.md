# 图像生成模块设计

## 1. 模块矩阵

| 文件 | 定位 | 特性 |
|------|------|------|
| [sdxl.py](../sdxl.py) | 高级用户自由调参 | 参数钳位宽松 |
| [sdxl_safe.py](../sdxl_safe.py) | 安全默认参数 | 严格钳位 + 设置预览 |
| [sdxl_safe_canny.py](../sdxl_safe_canny.py) | 安全 + Canny ControlNet | 精炼阶段支持边缘锁定 |

## 2. 模型选项

```python
MODEL_CHOICES = {
    "turbo":    "stabilityai/sd-turbo",                      # SD 2.1 Turbo, 非 SDXL
    "xl-turbo": "stabilityai/sdxl-turbo",                    # SDXL Turbo
    "normal":   "stabilityai/stable-diffusion-xl-base-1.0",  # SDXL Base 1.0
}
```

## 3. 生成流程

### 3.1 Draft → Optional Refine

```
用户 Prompt
    │
    ▼
┌──────────────────┐
│ Text2Image (Draft)│ ← get_t2i(model_key)
│  AutoPipeline     │
└────────┬─────────┘
         │ draft image
         ▼
    do_refine?
    ├── No → 输出 draft image
    └── Yes
         │
         ▼
    ┌──────────────────────┐
    │ Image2Image (Refine) │ ← get_i2i(model_key) 或
    │                      │   get_refine_i2i_with_controlnet()
    └──────────┬───────────┘
               │ refined image
               ▼
          输出最终图像
```

### 3.2 ControlNet 精炼路径（sdxl_safe_canny.py 独有）

```
draft image → canny_like() → 边缘图 (control_image)
                                     │
                                     ▼
StableDiffusionXLControlNetImg2ImgPipeline
├── image = draft image
├── control_image = 边缘图
├── controlnet_conditioning_scale = 用户设定
└── → refined image (结构锁定)
```

ControlNet 仅支持 SDXL 系列 refine model（`xl-turbo`, `normal`）。
选择 `turbo` 作为 refine model 时自动降级为普通 img2img。

Canny 边缘检测使用 PIL 内置 `FIND_EDGES`（无 OpenCV 依赖）：
```python
edges = im.convert("L").filter(ImageFilter.FIND_EDGES)
edges = edges.point(lambda p: 255 if p > 25 else 0)
```

## 4. 参数钳位策略（safe 系列）

### 4.1 Draft 参数

| 参数 | Turbo 系列 | Normal (SDXL Base) |
|------|------------|---------------------|
| steps | 1–8 | 35–500 |
| CFG | **强制 0.0** | 10.0–100.0 |
| 分辨率 | 256–1024 | 512–1024 |

### 4.2 Refine 参数

| 参数 | Turbo 系列 | Normal (同源 normal→normal) | Normal (异源) |
|------|------------|---------------------------|---------------|
| steps | 1–12 | 20–60 | 20–60 |
| CFG | **强制 0.0** | 3.0–8.0 | 3.0–8.0 |
| strength | 0.05–0.55 | **0.06–0.18** (防止 mosaic) | 0.10–0.55 |

**关键设计决策**：Normal→Normal 精炼时 strength 严格限制在低区间，
防止 SDXL Base 在 img2img 中产生"彩色玻璃/重复纹理"伪影。

## 5. Pipeline 缓存

```python
_T2I: Dict[str, pipeline]                    # model_key → Text2Image
_I2I: Dict[str, pipeline]                    # model_key → Image2Image
_CN:  Dict[str, ControlNetModel]             # control_key → ControlNet
_I2I_REFINE_CN: Dict[(str,str), pipeline]    # (model, control) → CN pipeline
```

所有 pipeline 首次使用时加载到 CPU，缓存后复用。

## 6. sdxl_safe.py 独有：实时设置预览

`explain_effective_settings()` 函数在任何控件变更时触发，
显示钳位后的实际参数值，帮助用户理解 slider 值经过归一化后的效果。
