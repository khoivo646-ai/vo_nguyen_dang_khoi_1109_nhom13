using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace nhom13.Models
{
    public class ChildDevice
    {
        [Key]
        public int Id { get; set; }

        [Required]
        public string ChildName { get; set; } = string.Empty; // Tên của trẻ em

        [Required]
        public string DeviceName { get; set; } = string.Empty; // Tên thiết bị (VD: iPhone của bé)

        // Quản lý thời gian sử dụng thiết bị (phút/ngày)
        public int ScreenTimeLimitMinutes { get; set; } = 120;

        // Khóa app (Danh sách ứng dụng bị hạn chế/chặn, VD: "TikTok, YouTube, Games")
        public string? BlockedApps { get; set; }

        // Khóa thiết bị từ xa (True: Bị khóa, False: Bình thường)
        public bool IsLocked { get; set; } = false;

        // Định vị vị trí thiết bị của trẻ
        public double Latitude { get; set; } = 10.8018;
        public double Longitude { get; set; } = 106.7144;

        // Liên kết với tài khoản Phụ huynh quản lý
        public string? ParentUsername { get; set; }

        // Liên kết với tài khoản đăng nhập của Trẻ em (nếu trẻ đăng nhập vào app)
        public string? ChildUsername { get; set; }

        public DateTime LastUpdated { get; set; } = DateTime.Now;

        // Thời điểm cập nhật vị trí gần nhất (để phụ huynh biết vị trí còn "mới" hay không)
        public DateTime? LocationUpdatedAt { get; set; }

        // ===== ĐO TIẾNG ỒN =====
        // Ngưỡng tiếng ồn (dB). Khi điện thoại của trẻ đo được mức >= ngưỡng sẽ sinh cảnh báo cho phụ huynh.
        public double NoiseThresholdDb { get; set; } = 80;

        // Mức tiếng ồn gần nhất đo được và thời điểm đo
        public double? LastNoiseDb { get; set; }
        public DateTime? LastNoiseAt { get; set; }

        // Thời điểm gửi email cảnh báo tiếng ồn gần nhất (chống spam email)
        public DateTime? LastNoiseAlertEmailAt { get; set; }

        [JsonIgnore]
        public List<NoiseEvent> NoiseEvents { get; set; } = new();
    }
}
