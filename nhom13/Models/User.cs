using Microsoft.AspNetCore.Identity;

namespace nhom13.Models
{
    public class User : IdentityUser
    {
        public string? Initials { get; set; }
        public string? FullName { get; set; }

        // Vector đặc trưng khuôn mặt (ArcFace 512 chiều, lưu dạng Base64 của mảng float).
        // KHÔNG lưu ảnh gốc để bảo vệ quyền riêng tư.
        public string? FaceEmbedding { get; set; }
        public DateTime? FaceRegisteredAt { get; set; }

        // Mã OTP được lưu dưới dạng HASH (SHA-256), không lưu mã gốc.
        public string? OtpCode { get; set; }
        public DateTime? OtpExpiry { get; set; }

        // Mục đích của OTP hiện tại: "ConfirmEmail" (xác minh email khi đăng ký) hoặc "Login" (đăng nhập 2 bước)
        public string? OtpPurpose { get; set; }

        // Số lần nhập sai OTP hiện tại (quá giới hạn sẽ hủy mã)
        public int OtpFailedCount { get; set; }
    }
}
