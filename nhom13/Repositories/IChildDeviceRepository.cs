using nhom13.Models;

namespace nhom13.Repositories
{
    public interface IChildDeviceRepository
    {
        // ownerUsername = null => lấy tất cả (Admin/Staff); ngược lại chỉ lấy thiết bị mà user là phụ huynh hoặc là trẻ được liên kết
        Task<IEnumerable<ChildDevice>> GetDevicesAsync(string? searchName = null, string? ownerUsername = null);
        Task<ChildDevice?> GetDeviceByIdAsync(int id);
        Task AddDeviceAsync(ChildDevice device);
        Task UpdateDeviceAsync(ChildDevice device);
        Task DeleteDeviceAsync(int id);
        Task<bool> UpdateLocationAsync(int id, double lat, double lng);

        // ===== Tiếng ồn =====
        Task AddNoiseEventAsync(ChildDevice device, NoiseEvent noiseEvent);
        Task<IEnumerable<NoiseEvent>> GetNoiseEventsAsync(int deviceId, DateTime? fromUtc, DateTime? toUtc, bool alertsOnly, int take);
        Task<IEnumerable<NoiseAlertDto>> GetUnacknowledgedAlertsAsync(string? ownerUsername, int take);
        Task<NoiseEvent?> GetNoiseEventAsync(long eventId);
        Task AcknowledgeNoiseEventAsync(NoiseEvent noiseEvent);
    }
}
