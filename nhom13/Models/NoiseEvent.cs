using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace nhom13.Models
{
    /// <summary>
    /// Một lần đo tiếng ồn do điện thoại của trẻ gửi lên.
    /// Nếu Decibel >= ngưỡng của thiết bị thì IsAlert = true (trẻ la hét / môi trường quá ồn).
    /// </summary>
    public class NoiseEvent
    {
        [Key]
        public long Id { get; set; }

        public int ChildDeviceId { get; set; }

        [JsonIgnore]
        public ChildDevice? ChildDevice { get; set; }

        // Mức âm thanh đo được (dB)
        public double Decibel { get; set; }

        // Mức đỉnh trong khoảng đo (nếu app gửi lên)
        public double? PeakDecibel { get; set; }

        // Thời lượng tiếng ồn kéo dài (giây)
        public int DurationSeconds { get; set; }

        // Ngưỡng áp dụng tại thời điểm đo
        public double ThresholdDb { get; set; }

        // Vượt ngưỡng => cảnh báo
        public bool IsAlert { get; set; }

        // Phụ huynh đã xem / xác nhận cảnh báo chưa
        public bool IsAcknowledged { get; set; }

        public DateTime MeasuredAt { get; set; } = DateTime.UtcNow;
    }
}
