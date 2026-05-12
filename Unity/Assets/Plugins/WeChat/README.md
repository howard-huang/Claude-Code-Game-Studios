This directory hosts the Tuanjie WeChat Mini Game transform SDK and any `.jslib`
WX-bridge files.

Source: https://github.com/wechat-miniprogram/minigame-tuanjie-transform-sdk

**Note:** The SDK is built for Tuanjie 团结 engine (Unity China fork, Unity 2022 LTS base).
When using pure Unity 2021.3 LTS, verify version compatibility before integrating.
See `CCGS/Docs/architecture/adr-0001-wx-sdk-adapter-layer.md`.

After cloning the SDK here, the `WxBridge.cs` adapter (per ADR-0001) consumes
the `.jslib` exports for `wx.*` calls.
