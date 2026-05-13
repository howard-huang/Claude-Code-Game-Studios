using System;
using WeChatWASM;

namespace CCGS.Core.Platform
{
    /// <summary>
    /// Thin Facade over <see cref="WX"/>. Provides namespace isolation and
    /// idiomatic C# callback shapes for the WeChat Mini Game runtime.
    /// All gameplay calls to <c>wx.*</c> go through this class; importing
    /// <c>WeChatWASM</c> outside <c>Core/Platform/</c> is forbidden (ADR-0001).
    /// </summary>
    public static class Wx
    {
        /// <summary>
        /// Wraps <see cref="WX.Login"/>. Invokes <paramref name="onCode"/> with
        /// the WeChat login code on success, or <paramref name="onError"/> with
        /// the SDK error message on failure.
        /// </summary>
        public static void Login(Action<string> onCode, Action<string> onError)
            => WX.Login(new LoginOption
            {
                success = res => onCode?.Invoke(res.code),
                fail = res => onError?.Invoke(res.errMsg),
            });
    }
}

