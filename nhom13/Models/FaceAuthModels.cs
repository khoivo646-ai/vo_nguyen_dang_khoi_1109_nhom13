using System.ComponentModel.DataAnnotations;

namespace nhom13.Models
{
    public class RegisterFaceModel
    {
        // Ảnh chụp khuôn mặt (JPEG/PNG) dạng Base64, chấp nhận cả tiền tố "data:image/jpeg;base64,".
        // Username được lấy từ JWT (người đang đăng nhập), không nhận từ client để tránh ghi đè khuôn mặt người khác.
        [Required]
        public string FaceDataBase64 { get; set; } = string.Empty;
    }

    public class FaceLoginModel
    {
        [Required]
        public string Username { get; set; } = string.Empty;

        [Required]
        public string FaceDataBase64 { get; set; } = string.Empty; // Ảnh khuôn mặt gửi lên để so khớp
    }
}
