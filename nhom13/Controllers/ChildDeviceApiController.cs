using System.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using nhom13.Models;
using nhom13.Repositories;
using nhom13.Services;

namespace nhom13.Controllers
{
    /// <summary>
    /// Quản lý thiết bị của trẻ. TẤT CẢ API đều yêu cầu JWT hợp lệ ([Authorize]).
    /// Phân quyền theo 3 role (Admin, Parent, Child):
    /// - Admin  : xem / thêm / sửa / xóa mọi thiết bị.
    /// - Parent : thêm thiết bị và xem / sửa / xóa chỉ những thiết bị do mình sở hữu (ParentUsername == mình).
    /// - Child  : chỉ được xem thiết bị gắn với tài khoản của mình (ChildUsername == mình)
    ///            và gửi vị trí GPS + mức tiếng ồn; KHÔNG được thêm / sửa / xóa thiết bị hay đổi ngưỡng cảnh báo.
    /// </summary>
    [Route("api/[controller]")]
    [ApiController]
    [Authorize]
    public class ChildDeviceApiController : ControllerBase
    {
        private readonly IChildDeviceRepository _deviceRepository;
        private readonly UserManager<User> _userManager;
        private readonly IEmailSender _emailSender;
        private readonly IConfiguration _configuration;
        private readonly ILogger<ChildDeviceApiController> _logger;

        public ChildDeviceApiController(
            IChildDeviceRepository deviceRepository,
            UserManager<User> userManager,
            IEmailSender emailSender,
            IConfiguration configuration,
            ILogger<ChildDeviceApiController> logger)
        {
            _deviceRepository = deviceRepository;
            _userManager = userManager;
            _emailSender = emailSender;
            _configuration = configuration;
            _logger = logger;
        }

        private string CurrentUsername => User.Identity?.Name ?? string.Empty;
        private bool IsAdmin => User.IsInRole(AppRoles.Admin);
        private bool IsParent => User.IsInRole(AppRoles.Parent);

        private bool IsParentOf(ChildDevice d) => string.Equals(d.ParentUsername, CurrentUsername, StringComparison.OrdinalIgnoreCase);
        private bool IsChildOf(ChildDevice d) => !string.IsNullOrEmpty(d.ChildUsername) && string.Equals(d.ChildUsername, CurrentUsername, StringComparison.OrdinalIgnoreCase);

        private bool CanView(ChildDevice d) => IsAdmin || (IsParent && IsParentOf(d)) || IsChildOf(d);
        private bool CanManage(ChildDevice d) => IsAdmin || (IsParent && IsParentOf(d));
        private bool CanReportFromDevice(ChildDevice d) => IsAdmin || (IsParent && IsParentOf(d)) || IsChildOf(d);

        private IActionResult NoPermission(string message = "Bạn không có quyền thao tác trên thiết bị này!") =>
            StatusCode(StatusCodes.Status403Forbidden, new { Status = false, Message = message });

        private IActionResult DeviceNotFound() =>
            NotFound(new { Status = false, Message = "Không tìm thấy thiết bị!" });

        // ======================= CRUD =======================

        // Lấy danh sách + tìm kiếm:
        // - Admin: thấy tất cả thiết bị.
        // - Parent: chỉ thấy thiết bị có ParentUsername == mình.
        // - Child: chỉ thấy thiết bị có ChildUsername == mình.
        [HttpGet]
        public async Task<IActionResult> GetDevices([FromQuery] string? search = null)
        {
            var owner = IsAdmin ? null : CurrentUsername;
            var devices = await _deviceRepository.GetDevicesAsync(search, owner);
            return Ok(devices);
        }

        [HttpGet("{id:int}")]
        public async Task<IActionResult> GetDeviceById(int id)
        {
            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanView(device)) return NoPermission();
            return Ok(device);
        }

        // Thêm thiết bị mới (chỉ Admin hoặc Parent; tài khoản Child không được tự thêm thiết bị).
        [Authorize(Roles = AppRoles.AdminOrParent)]
        [HttpPost]
        public async Task<IActionResult> AddDevice([FromBody] ChildDeviceUpsertModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            string parentUsername;
            if (IsAdmin && !string.IsNullOrWhiteSpace(model.ParentUsername))
            {
                if (await _userManager.FindByNameAsync(model.ParentUsername) == null)
                    return BadRequest(new { Status = false, Message = $"Không tồn tại tài khoản phụ huynh '{model.ParentUsername}'!" });
                parentUsername = model.ParentUsername.Trim();
            }
            else
            {
                parentUsername = CurrentUsername;
            }

            var childCheck = await ValidateChildUsernameAsync(model.ChildUsername);
            if (childCheck != null) return childCheck;

            var device = new ChildDevice { ParentUsername = parentUsername };
            ApplyModel(device, model);

            await _deviceRepository.AddDeviceAsync(device);
            return CreatedAtAction(nameof(GetDeviceById), new { id = device.Id }, device);
        }

        // Cập nhật: giới hạn thời gian, khóa app, khóa thiết bị từ xa, ngưỡng tiếng ồn... (chỉ Admin hoặc Parent sở hữu).
        [Authorize(Roles = AppRoles.AdminOrParent)]
        [HttpPut("{id:int}")]
        public async Task<IActionResult> UpdateDevice(int id, [FromBody] ChildDeviceUpsertModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (model.Id.HasValue && model.Id.Value != id) return BadRequest(new { Status = false, Message = "ID thiết bị không khớp." });

            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanManage(device)) return NoPermission();

            var childCheck = await ValidateChildUsernameAsync(model.ChildUsername);
            if (childCheck != null) return childCheck;

            // Chỉ Admin được chuyển thiết bị sang phụ huynh khác
            if (IsAdmin && !string.IsNullOrWhiteSpace(model.ParentUsername) &&
                !string.Equals(model.ParentUsername, device.ParentUsername, StringComparison.OrdinalIgnoreCase))
            {
                if (await _userManager.FindByNameAsync(model.ParentUsername) == null)
                    return BadRequest(new { Status = false, Message = $"Không tồn tại tài khoản phụ huynh '{model.ParentUsername}'!" });
                device.ParentUsername = model.ParentUsername.Trim();
            }

            ApplyModel(device, model);
            await _deviceRepository.UpdateDeviceAsync(device);
            return NoContent();
        }

        // Xóa thiết bị (chỉ Admin hoặc Parent sở hữu).
        [Authorize(Roles = AppRoles.AdminOrParent)]
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> DeleteDevice(int id)
        {
            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanManage(device)) return NoPermission("Chỉ Admin hoặc phụ huynh sở hữu mới được xóa thiết bị!");

            await _deviceRepository.DeleteDeviceAsync(id);
            return NoContent();
        }

        // ======================= VỊ TRÍ =======================

        // PUT: api/ChildDeviceApi/5/location (Điện thoại của trẻ hoặc phụ huynh cập nhật vị trí)
        [HttpPut("{id:int}/location")]
        public async Task<IActionResult> UpdateDeviceLocation(int id, [FromBody] UpdateLocationModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanReportFromDevice(device)) return NoPermission();

            await _deviceRepository.UpdateLocationAsync(id, model.Latitude, model.Longitude);
            return Ok(new { Status = true, Message = "Đã cập nhật vị trí thiết bị thành công!" });
        }

        // GET: api/ChildDeviceApi/5/location (Phụ huynh xem vị trí hiện tại của trẻ)
        [HttpGet("{id:int}/location")]
        public async Task<IActionResult> GetDeviceLocation(int id)
        {
            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanView(device)) return NoPermission();

            return Ok(new
            {
                device.Id,
                device.ChildName,
                device.Latitude,
                device.Longitude,
                device.LocationUpdatedAt
            });
        }

        // ======================= ĐO TIẾNG ỒN =======================

        // POST: api/ChildDeviceApi/5/noise
        // Điện thoại của trẻ đo âm thanh bằng micro và gửi mức dB lên; server so với ngưỡng để sinh cảnh báo.
        [HttpPost("{id:int}/noise")]
        public async Task<IActionResult> ReportNoise(int id, [FromBody] NoiseReadingModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanReportFromDevice(device)) return NoPermission();

            var measuredAt = model.MeasuredAt?.ToUniversalTime() ?? DateTime.UtcNow;
            if (measuredAt > DateTime.UtcNow.AddMinutes(5)) measuredAt = DateTime.UtcNow;

            var level = Math.Max(model.Decibel, model.PeakDecibel ?? 0);
            var noiseEvent = new NoiseEvent
            {
                Decibel = model.Decibel,
                PeakDecibel = model.PeakDecibel,
                DurationSeconds = model.DurationSeconds,
                ThresholdDb = device.NoiseThresholdDb,
                IsAlert = level >= device.NoiseThresholdDb,
                MeasuredAt = measuredAt
            };

            await _deviceRepository.AddNoiseEventAsync(device, noiseEvent);

            bool emailSent = false;
            if (noiseEvent.IsAlert)
            {
                emailSent = await TrySendNoiseAlertEmailAsync(device, noiseEvent);
            }

            return Ok(new
            {
                Status = true,
                noiseEvent.Id,
                noiseEvent.IsAlert,
                noiseEvent.Decibel,
                noiseEvent.ThresholdDb,
                ParentNotifiedByEmail = emailSent,
                Message = noiseEvent.IsAlert
                    ? $"CẢNH BÁO: Tiếng ồn {level:F0} dB vượt ngưỡng {device.NoiseThresholdDb:F0} dB!"
                    : "Đã ghi nhận mức tiếng ồn."
            });
        }

        // GET: api/ChildDeviceApi/5/noise?from=...&to=...&alertsOnly=true&take=100 (Lịch sử tiếng ồn)
        [HttpGet("{id:int}/noise")]
        public async Task<IActionResult> GetNoiseHistory(int id, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null,
            [FromQuery] bool alertsOnly = false, [FromQuery] int take = 100)
        {
            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanView(device)) return NoPermission();

            take = Math.Clamp(take, 1, 1000);
            var events = (await _deviceRepository.GetNoiseEventsAsync(id, from?.ToUniversalTime(), to?.ToUniversalTime(), alertsOnly, take)).ToList();

            return Ok(new
            {
                DeviceId = device.Id,
                device.ChildName,
                device.NoiseThresholdDb,
                device.LastNoiseDb,
                device.LastNoiseAt,
                Count = events.Count,
                AlertCount = events.Count(e => e.IsAlert),
                AverageDb = events.Count > 0 ? Math.Round(events.Average(e => e.Decibel), 1) : (double?)null,
                MaxDb = events.Count > 0 ? events.Max(e => Math.Max(e.Decibel, e.PeakDecibel ?? 0)) : (double?)null,
                Events = events
            });
        }

        // GET: api/ChildDeviceApi/noise-alerts (Phụ huynh / Admin lấy các cảnh báo tiếng ồn chưa xem)
        [Authorize(Roles = AppRoles.AdminOrParent)]
        [HttpGet("noise-alerts")]
        public async Task<IActionResult> GetNoiseAlerts([FromQuery] int take = 50)
        {
            var owner = IsAdmin ? null : CurrentUsername;
            var alerts = await _deviceRepository.GetUnacknowledgedAlertsAsync(owner, Math.Clamp(take, 1, 500));
            return Ok(alerts);
        }

        // PUT: api/ChildDeviceApi/noise-alerts/123/ack (Phụ huynh đánh dấu đã xem cảnh báo)
        [Authorize(Roles = AppRoles.AdminOrParent)]
        [HttpPut("noise-alerts/{eventId:long}/ack")]
        public async Task<IActionResult> AcknowledgeNoiseAlert(long eventId)
        {
            var noiseEvent = await _deviceRepository.GetNoiseEventAsync(eventId);
            if (noiseEvent?.ChildDevice == null) return NotFound(new { Status = false, Message = "Không tìm thấy cảnh báo!" });
            if (!CanManage(noiseEvent.ChildDevice)) return NoPermission();

            await _deviceRepository.AcknowledgeNoiseEventAsync(noiseEvent);
            return Ok(new { Status = true, Message = "Đã đánh dấu đã xem." });
        }

        // PUT: api/ChildDeviceApi/5/noise-threshold (Phụ huynh đặt ngưỡng dB cảnh báo; Child không được tự sửa)
        [Authorize(Roles = AppRoles.AdminOrParent)]
        [HttpPut("{id:int}/noise-threshold")]
        public async Task<IActionResult> UpdateNoiseThreshold(int id, [FromBody] NoiseThresholdModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var device = await _deviceRepository.GetDeviceByIdAsync(id);
            if (device == null) return DeviceNotFound();
            if (!CanManage(device)) return NoPermission();

            device.NoiseThresholdDb = model.ThresholdDb;
            await _deviceRepository.UpdateDeviceAsync(device);
            return Ok(new { Status = true, device.NoiseThresholdDb, Message = $"Đã đặt ngưỡng cảnh báo tiếng ồn {model.ThresholdDb:F0} dB." });
        }

        // ======================= HÀM PHỤ =======================

        private static void ApplyModel(ChildDevice device, ChildDeviceUpsertModel model)
        {
            device.ChildName = model.ChildName.Trim();
            device.DeviceName = model.DeviceName.Trim();
            device.ScreenTimeLimitMinutes = model.ScreenTimeLimitMinutes;
            device.BlockedApps = model.BlockedApps;
            device.IsLocked = model.IsLocked;
            if (model.Latitude.HasValue) device.Latitude = model.Latitude.Value;
            if (model.Longitude.HasValue) device.Longitude = model.Longitude.Value;
            if (model.ChildUsername != null) device.ChildUsername = string.IsNullOrWhiteSpace(model.ChildUsername) ? null : model.ChildUsername.Trim();
            if (model.NoiseThresholdDb.HasValue) device.NoiseThresholdDb = model.NoiseThresholdDb.Value;
        }

        private async Task<IActionResult?> ValidateChildUsernameAsync(string? childUsername)
        {
            if (string.IsNullOrWhiteSpace(childUsername)) return null;
            var childUser = await _userManager.FindByNameAsync(childUsername.Trim());
            if (childUser == null)
                return BadRequest(new { Status = false, Message = $"Không tồn tại tài khoản của trẻ '{childUsername}'!" });
            if (!await _userManager.IsInRoleAsync(childUser, AppRoles.Child))
                return BadRequest(new { Status = false, Message = $"Tài khoản '{childUsername}' không có vai trò 'Child' (Trẻ em)!" });
            return null;
        }

        private async Task<bool> TrySendNoiseAlertEmailAsync(ChildDevice device, NoiseEvent noiseEvent)
        {
            if (!_emailSender.IsConfigured || string.IsNullOrEmpty(device.ParentUsername)) return false;

            var cooldown = TimeSpan.FromMinutes(_configuration.GetValue("Noise:AlertEmailCooldownMinutes", 10));
            if (device.LastNoiseAlertEmailAt.HasValue && DateTime.UtcNow - device.LastNoiseAlertEmailAt.Value < cooldown)
                return false;

            var parent = await _userManager.FindByNameAsync(device.ParentUsername);
            if (parent?.Email == null) return false;

            var level = Math.Max(noiseEvent.Decibel, noiseEvent.PeakDecibel ?? 0);
            var body =
                $"<h3>Cảnh báo tiếng ồn từ thiết bị của {WebUtility.HtmlEncode(device.ChildName)}</h3>" +
                $"<p>Thiết bị <b>{WebUtility.HtmlEncode(device.DeviceName)}</b> vừa ghi nhận mức âm thanh " +
                $"<b style='color:#c62828'>{level:F0} dB</b> (ngưỡng {device.NoiseThresholdDb:F0} dB)" +
                (noiseEvent.DurationSeconds > 0 ? $", kéo dài {noiseEvent.DurationSeconds} giây" : "") + ".</p>" +
                $"<p>Thời điểm: {noiseEvent.MeasuredAt.ToLocalTime():dd/MM/yyyy HH:mm:ss}</p>" +
                $"<p>Vị trí gần nhất: <a href='https://www.google.com/maps?q={device.Latitude.ToString(System.Globalization.CultureInfo.InvariantCulture)},{device.Longitude.ToString(System.Globalization.CultureInfo.InvariantCulture)}'>Xem bản đồ</a></p>";

            try
            {
                await _emailSender.SendAsync(parent.Email, $"[KidGuard] Cảnh báo tiếng ồn - {device.ChildName}", body);
                device.LastNoiseAlertEmailAt = DateTime.UtcNow;
                await _deviceRepository.UpdateDeviceAsync(device);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Không gửi được email cảnh báo tiếng ồn cho {Parent}", device.ParentUsername);
                return false;
            }
        }
    }
}
