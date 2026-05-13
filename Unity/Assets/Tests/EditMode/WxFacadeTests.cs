using CCGS.Core.Platform;
using NUnit.Framework;

namespace CCGS.Tests.EditMode
{
    public class WxFacadeTests
    {
        [Test]
        public void Wx_Login_InvokesWithoutThrowing()
        {
            string capturedCode = null;
            string capturedError = null;

            Assert.DoesNotThrow(() => Wx.Login(
                onCode: code => capturedCode = code,
                onError: err => capturedError = err));
        }

        [Test]
        public void Wx_Login_AcceptsNullCallbacks()
        {
            Assert.DoesNotThrow(() => Wx.Login(onCode: null, onError: null));
        }
    }
}
