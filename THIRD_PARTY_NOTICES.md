# Third-Party Notices

VideoAI is built on open-source software and external runtimes created by other people and organizations.

The root `LICENSE` file applies to VideoAI's own source code. Third-party software remains governed by its own copyright and license terms. This file is informational and is not legal advice.

## Core upstream dependency

### analysis-video

- Project: https://github.com/hwanyong/analysis-video
- Attribution: **@hwanyong** and contributors
- Role: core video-analysis workflow, frame extraction/context generation, transcript integration
- Version used by VideoAI: `0.1.1`
- Upstream license: **MIT**

VideoAI builds its own orchestration, evidence-selection/package layer, acquisition workflows, provenance, GUI, and validation around this project.

## Acquisition/runtime projects

### yt-dlp

- Project: https://github.com/yt-dlp/yt-dlp
- Role: YouTube media/metadata/subtitle acquisition
- Upstream repository/PyPI source/wheel licensing: **Unlicense**

yt-dlp's upstream documentation notes that some prebuilt executables can include components under additional licenses. VideoAI does not bundle a yt-dlp executable in this repository.

### Playwright Python

- Project: https://github.com/microsoft/playwright-python
- Role: browser automation for TikTok public-player acquisition
- Upstream license: **Apache-2.0**

### Requests

- Project: https://github.com/psf/requests
- Role: HTTP session/download handling in TikTok acquisition
- Upstream license: **Apache-2.0**

### uv

- Project: https://github.com/astral-sh/uv
- Role: isolated Python dependency/runtime execution
- Upstream licensing: **Apache-2.0 OR MIT**

### Deno

- Project: https://github.com/denoland/deno
- Role: JavaScript runtime used by the current YouTube/yt-dlp workflow where needed
- Upstream license: **MIT**

## Image/video processing

### OpenCV

- Project: https://github.com/opencv/opencv
- Role: image decoding and evidence image operations
- Modern upstream license: **Apache-2.0**

### NumPy

- Project: https://github.com/numpy/numpy
- Role: numerical/image-array operations
- Upstream license: **BSD-3-Clause**

### Pillow

- Project: https://github.com/python-pillow/Pillow
- Role: image loading, drawing, fonts, contact sheets
- Upstream license: **MIT-CMU**

### FFmpeg / ffprobe

- Project: https://ffmpeg.org/
- Source mirror: https://github.com/FFmpeg/FFmpeg
- Role: media probing/processing used by VideoAI and its dependency stack

FFmpeg licensing depends on how a particular build is configured. Much of FFmpeg is LGPL-2.1-or-later, while enabling optional GPL components can make a build GPL-covered.

VideoAI does **not** redistribute an FFmpeg binary in this repository. Users are responsible for the license terms of the FFmpeg build they install.

### PyAV

- Project: https://github.com/PyAV-Org/PyAV
- Role: Python bindings around FFmpeg used by the broader analysis stack
- Source license: **BSD-3-Clause**

Binary wheels can include FFmpeg libraries with their own applicable terms.

### PySceneDetect

- Project: https://github.com/Breakthrough/PySceneDetect
- Attribution: Brandon Castellano and contributors
- Role: scene/cut detection in the broader analysis stack
- Upstream license: **BSD-3-Clause**

### scikit-image

- Project: https://github.com/scikit-image/scikit-image
- Role: image-analysis functionality in the broader stack
- Primary upstream license: **BSD-3-Clause**

The upstream license file contains additional per-file notices.

## Speech-to-text / inference

### faster-whisper

- Project: https://github.com/SYSTRAN/faster-whisper
- Role: Whisper speech-to-text
- Upstream license: **MIT**

### CTranslate2

- Project: https://github.com/OpenNMT/CTranslate2
- Role: optimized inference runtime used by faster-whisper
- Upstream license: **MIT**

## NVIDIA runtime components

The validated GPU path uses NVIDIA CUDA-related runtime components, including modules exposing `nvidia.cublas` and `nvidia.cudnn`.

NVIDIA drivers, CUDA, cuBLAS, cuDNN, and related runtime packages are external software governed by NVIDIA's applicable terms. VideoAI does not claim ownership of them.

## Browser runtime

The current TikTok workflow was validated using an installed Google Chrome browser driven by Playwright.

Google Chrome is external software and is not distributed by this repository. Its use is subject to Google's applicable terms.

## Transitive dependencies

Installing the projects above can install additional dependencies not individually listed here. Those packages retain their own licenses.

## No transfer of third-party ownership

VideoAI's MIT license does not:

- transfer ownership of third-party software;
- relicense third-party software;
- grant rights an upstream project does not grant;
- override platform or content licensing terms.

## Missing credit?

If you believe your repository, code, research, documentation, or public example materially influenced VideoAI and should be acknowledged here, open an issue:

https://github.com/abcedi/VideoAI/issues

The goal is to credit upstream work accurately and generously.
