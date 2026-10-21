using Microsoft.EntityFrameworkCore;
using nhom13.Models;

namespace nhom13.Repositories
{
    public class ChildDeviceRepository : IChildDeviceRepository
    {
        private readonly ApplicationDbContext _context;

        public ChildDeviceRepository(ApplicationDbContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<ChildDevice>> GetDevicesAsync(string? searchName = null, string? ownerUsername = null)
        {
            var query = _context.ChildDevices.AsNoTracking().AsQueryable();
            if (!string.IsNullOrEmpty(ownerUsername))
            {
                query = query.Where(d => d.ParentUsername == ownerUsername || d.ChildUsername == ownerUsername);
            }
            if (!string.IsNullOrWhiteSpace(searchName))
            {
                query = query.Where(d => d.ChildName.Contains(searchName) || d.DeviceName.Contains(searchName));
            }
            return await query.OrderByDescending(d => d.LastUpdated).ToListAsync();
        }

        public async Task<ChildDevice?> GetDeviceByIdAsync(int id)
        {
            return await _context.ChildDevices.FindAsync(id);
        }

        public async Task AddDeviceAsync(ChildDevice device)
        {
            device.LastUpdated = DateTime.Now;
            _context.ChildDevices.Add(device);
            await _context.SaveChangesAsync();
        }

        public async Task UpdateDeviceAsync(ChildDevice device)
        {
            device.LastUpdated = DateTime.Now;
            if (_context.Entry(device).State == EntityState.Detached)
            {
                _context.Entry(device).State = EntityState.Modified;
            }
            await _context.SaveChangesAsync();
        }

        public async Task DeleteDeviceAsync(int id)
        {
            var device = await _context.ChildDevices.FindAsync(id);
            if (device != null)
            {
                _context.ChildDevices.Remove(device);
                await _context.SaveChangesAsync();
            }
        }

        public async Task<bool> UpdateLocationAsync(int id, double lat, double lng)
        {
            var device = await _context.ChildDevices.FindAsync(id);
            if (device == null) return false;
            device.Latitude = lat;
            device.Longitude = lng;
            device.LastUpdated = DateTime.Now;
            device.LocationUpdatedAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();
            return true;
        }

        // ===== Tiếng ồn =====

        public async Task AddNoiseEventAsync(ChildDevice device, NoiseEvent noiseEvent)
        {
            noiseEvent.ChildDeviceId = device.Id;
            _context.NoiseEvents.Add(noiseEvent);
            device.LastNoiseDb = noiseEvent.Decibel;
            device.LastNoiseAt = noiseEvent.MeasuredAt;
            await _context.SaveChangesAsync();
        }

        public async Task<IEnumerable<NoiseEvent>> GetNoiseEventsAsync(int deviceId, DateTime? fromUtc, DateTime? toUtc, bool alertsOnly, int take)
        {
            var query = _context.NoiseEvents.AsNoTracking().Where(n => n.ChildDeviceId == deviceId);
            if (fromUtc.HasValue) query = query.Where(n => n.MeasuredAt >= fromUtc.Value);
            if (toUtc.HasValue) query = query.Where(n => n.MeasuredAt <= toUtc.Value);
            if (alertsOnly) query = query.Where(n => n.IsAlert);
            return await query.OrderByDescending(n => n.MeasuredAt).Take(take).ToListAsync();
        }

        public async Task<IEnumerable<NoiseAlertDto>> GetUnacknowledgedAlertsAsync(string? ownerUsername, int take)
        {
            var query = _context.NoiseEvents.AsNoTracking()
                .Where(n => n.IsAlert && !n.IsAcknowledged);
            if (!string.IsNullOrEmpty(ownerUsername))
            {
                query = query.Where(n => n.ChildDevice!.ParentUsername == ownerUsername);
            }
            return await query
                .OrderByDescending(n => n.MeasuredAt)
                .Take(take)
                .Select(n => new NoiseAlertDto(
                    n.Id,
                    n.ChildDeviceId,
                    n.ChildDevice!.ChildName,
                    n.ChildDevice.DeviceName,
                    n.Decibel,
                    n.PeakDecibel,
                    n.DurationSeconds,
                    n.ThresholdDb,
                    n.MeasuredAt))
                .ToListAsync();
        }

        public async Task<NoiseEvent?> GetNoiseEventAsync(long eventId)
        {
            return await _context.NoiseEvents.Include(n => n.ChildDevice).FirstOrDefaultAsync(n => n.Id == eventId);
        }

        public async Task AcknowledgeNoiseEventAsync(NoiseEvent noiseEvent)
        {
            noiseEvent.IsAcknowledged = true;
            await _context.SaveChangesAsync();
        }
    }
}
