using System.ComponentModel.DataAnnotations;

namespace nhom13.Models
{
    /// <summary>
    /// Dữ liệu client được phép gửi khi thêm/sửa thiết bị (tránh over-posting các trường hệ thống).
    /// Tên thuộc tính trùng với model Flutter nên app cũ vẫn gửi được.
    /// </summary>
    public class ChildDeviceUpsertModel
    {
        public int? Id { get; set; }

        [Required, StringLength(100)]
        public string ChildName { get; set; } = string.Empty;

        [Required, StringLength(100)]
        public string DeviceName { get; set; } = string.Empty;

        [Range(0, 24 * 60)]
        public int ScreenTimeLimitMinutes { get; set; } = 120;

        public string? BlockedApps { get; set; }

        public bool IsLocked { get; set; }

        [Range(-90, 90)]
        public double? Latitude { get; set; }

        [Range(-180, 180)]
        public double? Longitude { get; set; }

        // Chỉ Admin mới được chỉ định phụ huynh khác; Parent luôn bị gán = chính mình.
        public string? ParentUsername { get; set; }

        // Tài khoản của trẻ đăng nhập trên điện thoại (dùng để gửi vị trí / tiếng ồn).
        public string? ChildUsername { get; set; }

        [Range(30, 140)]
        public double? NoiseThresholdDb { get; set; }
    }

    public class NoiseReadingModel
    {
        // Mức âm thanh trung bình đo được (dB). Điện thoại thường cho giá trị 0 - 120 dB.
        [Range(0, 150)]
        public double Decibel { get; set; }

        [Range(0, 150)]
        public double? PeakDecibel { get; set; }

        // Thời lượng tiếng ồn kéo dài (giây)
        [Range(0, 3600)]
        public int DurationSeconds { get; set; }

        // Thời điểm đo trên điện thoại (UTC). Bỏ trống => dùng giờ server.
        public DateTime? MeasuredAt { get; set; }
    }

    public class NoiseThresholdModel
    {
        [Range(30, 140)]
        public double ThresholdDb { get; set; }
    }

    public record NoiseAlertDto(
        long Id,
        int ChildDeviceId,
        string ChildName,
        string DeviceName,
        double Decibel,
        double? PeakDecibel,
        int DurationSeconds,
        double ThresholdDb,
        DateTime MeasuredAt);

    public class SetRoleModel
    {
        [Required]
        public string Role { get; set; } = string.Empty;
    }
}
