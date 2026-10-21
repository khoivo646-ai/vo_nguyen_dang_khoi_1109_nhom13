using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using nhom13.Models;

namespace nhom13.Services
{
    public static class OtpPurposes
    {
        public const string ConfirmEmail = "ConfirmEmail";
        public const string Login = "Login";
    }

    public enum OtpVerifyResult
    {
        Success,
        Invalid,
        Expired,
        TooManyAttempts,
        NotIssued
    }

    /// <summary>
    /// Sinh và kiểm tra mã OTP 6 số.
    /// - Sinh bằng RandomNumberGenerator (an toàn mật mã), không dùng System.Random.
    /// - Chỉ lưu HMAC-SHA256 của mã trong CSDL (lộ DB cũng không lộ OTP).
    /// - Mỗi mã gắn với 1 mục đích (xác minh email / đăng nhập), có hạn dùng, dùng 1 lần,
    ///   nhập sai quá MaxAttempts lần thì mã bị hủy.
    /// </summary>
    public class OtpService
    {
        public const int MaxAttempts = 5;

        private readonly UserManager<User> _userManager;
        private readonly byte[] _hmacKey;

        public OtpService(UserManager<User> userManager, IConfiguration configuration)
        {
            _userManager = userManager;
            _hmacKey = Encoding.UTF8.GetBytes(configuration["JWTKey:Secret"] ?? throw new InvalidOperationException("Thiếu JWTKey:Secret"));
        }

        public async Task<string> GenerateAsync(User user, string purpose, TimeSpan lifetime)
        {
            var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");

            user.OtpCode = Hash(user.Id, purpose, code);
            user.OtpPurpose = purpose;
            user.OtpExpiry = DateTime.UtcNow.Add(lifetime);
            user.OtpFailedCount = 0;
            await _userManager.UpdateAsync(user);

            return code;
        }

        public async Task<OtpVerifyResult> VerifyAsync(User user, string purpose, string code)
        {
            if (string.IsNullOrEmpty(user.OtpCode) || user.OtpPurpose != purpose || user.OtpExpiry == null)
                return OtpVerifyResult.NotIssued;

            if (user.OtpExpiry < DateTime.UtcNow)
            {
                await ClearAsync(user);
                return OtpVerifyResult.Expired;
            }

            var expected = Convert.FromHexString(user.OtpCode);
            var actual = Convert.FromHexString(Hash(user.Id, purpose, code.Trim()));

            if (!CryptographicOperations.FixedTimeEquals(expected, actual))
            {
                user.OtpFailedCount++;
                if (user.OtpFailedCount >= MaxAttempts)
                {
                    await ClearAsync(user);
                    return OtpVerifyResult.TooManyAttempts;
                }
                await _userManager.UpdateAsync(user);
                return OtpVerifyResult.Invalid;
            }

            // Dùng 1 lần: xóa ngay sau khi xác thực thành công
            await ClearAsync(user);
            return OtpVerifyResult.Success;
        }

        public static string Describe(OtpVerifyResult result) => result switch
        {
            OtpVerifyResult.Expired => "Mã OTP đã hết hạn, vui lòng yêu cầu mã mới!",
            OtpVerifyResult.TooManyAttempts => $"Nhập sai quá {MaxAttempts} lần, mã OTP đã bị hủy. Vui lòng yêu cầu mã mới!",
            OtpVerifyResult.NotIssued => "Chưa có mã OTP hợp lệ, vui lòng yêu cầu mã mới!",
            _ => "Mã OTP không chính xác!"
        };

        private async Task ClearAsync(User user)
        {
            user.OtpCode = null;
            user.OtpPurpose = null;
            user.OtpExpiry = null;
            user.OtpFailedCount = 0;
            await _userManager.UpdateAsync(user);
        }

        private string Hash(string userId, string purpose, string code)
        {
            var data = Encoding.UTF8.GetBytes($"{userId}:{purpose}:{code}");
            return Convert.ToHexString(HMACSHA256.HashData(_hmacKey, data));
        }
    }
}
