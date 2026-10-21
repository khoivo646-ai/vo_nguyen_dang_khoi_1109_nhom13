using System.Net;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using nhom13.Models;
using nhom13.Services;

namespace nhom13.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    [EnableRateLimiting("auth")]
    public class AuthenticateController : ControllerBase
    {
        private static readonly TimeSpan LoginOtpLifetime = TimeSpan.FromMinutes(5);
        private static readonly TimeSpan ConfirmEmailLifetime = TimeSpan.FromMinutes(30);

        private readonly UserManager<User> _userManager;
        private readonly IConfiguration _configuration;
        private readonly OtpService _otpService;
        private readonly TokenService _tokenService;
        private readonly IEmailSender _emailSender;
        private readonly FaceRecognitionService _faceService;
        private readonly ApplicationDbContext _dbContext;
        private readonly ILogger<AuthenticateController> _logger;

        public AuthenticateController(
            UserManager<User> userManager,
            IConfiguration configuration,
            OtpService otpService,
            TokenService tokenService,
            IEmailSender emailSender,
            FaceRecognitionService faceService,
            ApplicationDbContext dbContext,
            ILogger<AuthenticateController> logger)
        {
            _userManager = userManager;
            _configuration = configuration;
            _otpService = otpService;
            _tokenService = tokenService;
            _emailSender = emailSender;
            _faceService = faceService;
            _dbContext = dbContext;
            _logger = logger;
        }

        // 1. ĐĂNG KÝ TÀI KHOẢN QUA EMAIL (chỉ được chọn Parent hoặc Child) + GỬI MÃ XÁC MINH EMAIL
        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegistrationModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            // Chặn người dùng tự chọn quyền Admin khi đăng ký
            string requestedRole = string.IsNullOrWhiteSpace(model.Role) ? AppRoles.Parent : model.Role.Trim();
            if (!AppRoles.IsSelfRegistrable(requestedRole))
            {
                return StatusCode(StatusCodes.Status403Forbidden, new
                {
                    Status = false,
                    Message = "Khi tự đăng ký chỉ được chọn vai trò 'Parent' (Phụ huynh) hoặc 'Child' (Trẻ em). Không được tự đăng ký quyền Admin!"
                });
            }
            string assignedRole = AppRoles.Normalize(requestedRole)!;

            if (await _userManager.FindByNameAsync(model.Username) != null)
                return BadRequest(new { Status = false, Message = "Tài khoản đã tồn tại!" });

            if (await _userManager.FindByEmailAsync(model.Email) != null)
                return BadRequest(new { Status = false, Message = "Email này đã được đăng ký!" });

            if (!_emailSender.IsConfigured)
                return EmailNotConfigured();

            var user = new User
            {
                UserName = model.Username,
                Email = model.Email,
                Initials = model.Initials,
                EmailConfirmed = false
            };

            var result = await _userManager.CreateAsync(user, model.Password);
            if (!result.Succeeded)
            {
                var errors = string.Join("; ", result.Errors.Select(e => e.Description));
                return BadRequest(new { Status = false, Message = $"Lỗi tạo tài khoản: {errors}" });
            }

            await _userManager.AddToRoleAsync(user, assignedRole);

            if (!await SendConfirmEmailAsync(user))
            {
                // Gửi email thất bại => xóa tài khoản vừa tạo để người dùng đăng ký lại được
                await _userManager.DeleteAsync(user);
                return StatusCode(StatusCodes.Status503ServiceUnavailable,
                    new { Status = false, Message = "Không gửi được email xác minh. Vui lòng kiểm tra lại địa chỉ email hoặc thử lại sau!" });
            }

            return Ok(new
            {
                Status = true,
                RequiresEmailConfirmation = true,
                Email = MaskEmail(user.Email!),
                Message = $"Đăng ký thành công! Mã xác minh đã được gửi tới {MaskEmail(user.Email!)}. Vui lòng xác minh email trước khi đăng nhập."
            });
        }

        // 1b. XÁC MINH EMAIL BẰNG MÃ 6 SỐ (dùng trong app)
        [HttpPost("confirm-email")]
        public async Task<IActionResult> ConfirmEmail([FromBody] ConfirmEmailModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var (ok, message) = await ConfirmEmailCoreAsync(model.Email, model.Code);
            return ok ? Ok(new { Status = true, Message = message }) : BadRequest(new { Status = false, Message = message });
        }

        // 1c. XÁC MINH EMAIL BẰNG LINK TRONG EMAIL (mở bằng trình duyệt)
        [HttpGet("confirm-email")]
        public async Task<IActionResult> ConfirmEmailByLink([FromQuery] string email, [FromQuery] string code)
        {
            var (ok, message) = await ConfirmEmailCoreAsync(email ?? "", code ?? "");
            var color = ok ? "#2e7d32" : "#c62828";
            var html = $"<html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>KidGuard</title></head>" +
                       $"<body style='font-family:sans-serif;text-align:center;padding-top:60px'>" +
                       $"<h2 style='color:{color}'>{WebUtility.HtmlEncode(message)}</h2>" +
                       $"<p>Bạn có thể quay lại ứng dụng KidGuard.</p></body></html>";
            return Content(html, "text/html; charset=utf-8");
        }

        // 1d. GỬI LẠI MÃ XÁC MINH EMAIL
        [HttpPost("resend-confirmation")]
        public async Task<IActionResult> ResendConfirmation([FromBody] ResendConfirmationModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (!_emailSender.IsConfigured) return EmailNotConfigured();

            var user = await _userManager.FindByEmailAsync(model.Email);
            if (user != null && !user.EmailConfirmed)
            {
                if (!await SendConfirmEmailAsync(user))
                    return StatusCode(StatusCodes.Status503ServiceUnavailable, new { Status = false, Message = "Không gửi được email, vui lòng thử lại sau!" });
            }

            // Trả thông báo chung để không lộ email nào đã đăng ký
            return Ok(new { Status = true, Message = "Nếu email tồn tại và chưa xác minh, mã mới đã được gửi." });
        }

        // 2. BƯỚC 1 ĐĂNG NHẬP: KIỂM TRA TÀI KHOẢN + MẬT KHẨU & GỬI OTP QUA EMAIL
        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var user = await _userManager.FindByNameAsync(model.Username);
            if (user == null)
                return Unauthorized(new { Status = false, Message = "Sai tên đăng nhập hoặc mật khẩu!" });

            if (await _userManager.IsLockedOutAsync(user))
                return LockedOut(user);

            if (!await _userManager.CheckPasswordAsync(user, model.Password))
            {
                await _userManager.AccessFailedAsync(user);
                if (await _userManager.IsLockedOutAsync(user)) return LockedOut(user);
                return Unauthorized(new { Status = false, Message = "Sai tên đăng nhập hoặc mật khẩu!" });
            }

            if (!user.EmailConfirmed)
            {
                return StatusCode(StatusCodes.Status403Forbidden, new
                {
                    Status = false,
                    RequiresEmailConfirmation = true,
                    Email = MaskEmail(user.Email!),
                    Message = "Email chưa được xác minh! Vui lòng kiểm tra hộp thư hoặc yêu cầu gửi lại mã xác minh."
                });
            }

            if (!_emailSender.IsConfigured) return EmailNotConfigured();

            await _userManager.ResetAccessFailedCountAsync(user);

            var otp = await _otpService.GenerateAsync(user, OtpPurposes.Login, LoginOtpLifetime);
            var body =
                $"<h3>Xin chào {WebUtility.HtmlEncode(user.UserName)},</h3>" +
                $"<p>Mã OTP đăng nhập KidGuard của bạn là:</p>" +
                $"<p style='color:#1565c0;font-size:28px;font-weight:bold;letter-spacing:6px'>{otp}</p>" +
                $"<p>Mã có hiệu lực trong {LoginOtpLifetime.TotalMinutes} phút và chỉ dùng được 1 lần.</p>" +
                $"<p>Nếu không phải bạn đăng nhập, hãy đổi mật khẩu ngay.</p>";

            try
            {
                await _emailSender.SendAsync(user.Email!, "[KidGuard] Mã xác thực đăng nhập OTP", body);
            }
            catch (Exception)
            {
                return StatusCode(StatusCodes.Status503ServiceUnavailable,
                    new { Status = false, Message = "Không gửi được email OTP, vui lòng thử lại sau!" });
            }

            // KHÔNG trả mã OTP về client => người đăng nhập buộc phải mở email để lấy mã (chứng minh sở hữu email)
            return Ok(new
            {
                Status = true,
                RequiresOtp = true,
                Email = MaskEmail(user.Email!),
                ExpiresInSeconds = (int)LoginOtpLifetime.TotalSeconds,
                Message = $"Mã OTP đã được gửi tới email {MaskEmail(user.Email!)}"
            });
        }

        // 3. BƯỚC 2 ĐĂNG NHẬP: XÁC THỰC MÃ OTP & TRẢ VỀ JWT TOKEN KÈM ROLE
        [HttpPost("verify-otp")]
        public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var user = await _userManager.FindByNameAsync(model.Username);
            if (user == null)
                return BadRequest(new { Status = false, Message = "Mã OTP không chính xác hoặc đã hết hạn!" });

            if (await _userManager.IsLockedOutAsync(user))
                return LockedOut(user);

            var result = await _otpService.VerifyAsync(user, OtpPurposes.Login, model.OtpCode);
            if (result != OtpVerifyResult.Success)
                return BadRequest(new { Status = false, Message = OtpService.Describe(result) });

            return await IssueTokenAsync(user, "Xác thực OTP và đăng nhập thành công!");
        }

        // 4. ĐĂNG KÝ / CẬP NHẬT KHUÔN MẶT (bắt buộc đã đăng nhập, chỉ cập nhật được khuôn mặt của CHÍNH MÌNH)
        [Authorize]
        [HttpPost("register-face")]
        [RequestSizeLimit(10 * 1024 * 1024)]
        public async Task<IActionResult> RegisterFace([FromBody] RegisterFaceModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var user = await _userManager.FindByNameAsync(User.Identity!.Name!);
            if (user == null)
                return NotFound(new { Status = false, Message = "Không tìm thấy người dùng!" });

            var extract = _faceService.ExtractEmbedding(model.FaceDataBase64);
            if (!extract.Success)
                return BadRequest(new { Status = false, Message = extract.Error });

            user.FaceEmbedding = FaceRecognitionService.Serialize(extract.Embedding!);
            user.FaceRegisteredAt = DateTime.UtcNow;
            var result = await _userManager.UpdateAsync(user);

            if (!result.Succeeded)
                return StatusCode(500, new { Status = false, Message = "Lưu dữ liệu khuôn mặt thất bại!" });

            return Ok(new { Status = true, Message = "Đăng ký khuôn mặt thành công!" });
        }

        // 4b. XÓA DỮ LIỆU KHUÔN MẶT CỦA CHÍNH MÌNH
        [Authorize]
        [HttpDelete("face")]
        public async Task<IActionResult> DeleteFace()
        {
            var user = await _userManager.FindByNameAsync(User.Identity!.Name!);
            if (user == null) return NotFound(new { Status = false, Message = "Không tìm thấy người dùng!" });

            user.FaceEmbedding = null;
            user.FaceRegisteredAt = null;
            await _userManager.UpdateAsync(user);
            return Ok(new { Status = true, Message = "Đã xóa dữ liệu khuôn mặt." });
        }

        // 5. ĐĂNG NHẬP BẰNG KHUÔN MẶT: so khớp vector đặc trưng ArcFace bằng cosine similarity
        [HttpPost("login-face")]
        [RequestSizeLimit(10 * 1024 * 1024)]
        public async Task<IActionResult> LoginWithFace([FromBody] FaceLoginModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var user = await _userManager.FindByNameAsync(model.Username);
            if (user == null)
                return Unauthorized(new { Status = false, Message = "Tài khoản không tồn tại!" });

            if (await _userManager.IsLockedOutAsync(user))
                return LockedOut(user);

            if (!user.EmailConfirmed)
                return StatusCode(StatusCodes.Status403Forbidden, new { Status = false, RequiresEmailConfirmation = true, Message = "Email chưa được xác minh!" });

            var stored = FaceRecognitionService.Deserialize(user.FaceEmbedding);
            if (stored == null)
                return BadRequest(new { Status = false, Message = "Tài khoản này chưa đăng ký khuôn mặt!" });

            var extract = _faceService.ExtractEmbedding(model.FaceDataBase64);
            if (!extract.Success)
                return BadRequest(new { Status = false, Message = extract.Error });

            var similarity = FaceRecognitionService.CosineSimilarity(stored, extract.Embedding!);
            _logger.LogInformation("Face login {User}: similarity={Similarity:F3}, threshold={Threshold}", user.UserName, similarity, _faceService.MatchThreshold);

            if (similarity < _faceService.MatchThreshold)
            {
                await _userManager.AccessFailedAsync(user);
                if (await _userManager.IsLockedOutAsync(user)) return LockedOut(user);
                return Unauthorized(new
                {
                    Status = false,
                    Similarity = Math.Round(similarity, 3),
                    Message = "Khuôn mặt không khớp, đăng nhập thất bại!"
                });
            }

            await _userManager.ResetAccessFailedCountAsync(user);
            return await IssueTokenAsync(user, "Đăng nhập bằng khuôn mặt thành công!", Math.Round(similarity, 3));
        }

        // 6. THÔNG TIN NGƯỜI DÙNG HIỆN TẠI (Flutter dùng để kiểm tra token & điều hướng đúng màn hình theo role)
        [Authorize]
        [HttpGet("me")]
        public async Task<IActionResult> Me()
        {
            var user = await _userManager.FindByNameAsync(User.Identity!.Name!);
            if (user == null) return NotFound();
            var roles = await _userManager.GetRolesAsync(user);
            return Ok(new
            {
                Username = user.UserName,
                user.Email,
                user.Initials,
                Role = TokenService.GetPrimaryRole(roles),
                Roles = roles,
                HasFace = !string.IsNullOrEmpty(user.FaceEmbedding),
                user.EmailConfirmed
            });
        }

        // 7. XÁC NHẬN MẬT KHẨU CỦA PHỤ HUYNH KHI TRẺ EM MUỐN ĐĂNG XUẤT
        // Tìm thiết bị gắn với tài khoản trẻ (hoặc theo DeviceId), lấy ParentUsername và kiểm tra mật khẩu phụ huynh.
        [Authorize]
        [HttpPost("verify-parent-password")]
        public async Task<IActionResult> VerifyParentPassword([FromBody] VerifyParentPasswordModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var currentUsername = User.Identity?.Name ?? string.Empty;
            var currentUser = await _userManager.FindByNameAsync(currentUsername);
            if (currentUser == null)
                return Unauthorized(new { Status = false, Message = "Phiên đăng nhập không hợp lệ!" });

            // Tìm danh sách username phụ huynh liên kết với thiết bị của trẻ
            var candidateParentNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            if (model.DeviceId.HasValue)
            {
                var dev = await _dbContext.ChildDevices.FindAsync(model.DeviceId.Value);
                if (dev != null && !string.IsNullOrWhiteSpace(dev.ParentUsername))
                    candidateParentNames.Add(dev.ParentUsername);
            }

            var linkedParents = _dbContext.ChildDevices
                .Where(d => d.ChildUsername == currentUsername && d.ParentUsername != null)
                .Select(d => d.ParentUsername!)
                .Distinct()
                .ToList();
            foreach (var p in linkedParents) candidateParentNames.Add(p);

            // Kiểm tra mật khẩu với phụ huynh quản lý thiết bị của trẻ
            foreach (var parentName in candidateParentNames)
            {
                var parentUser = await _userManager.FindByNameAsync(parentName);
                if (parentUser != null && await _userManager.CheckPasswordAsync(parentUser, model.ParentPassword))
                {
                    return Ok(new
                    {
                        Status = true,
                        ParentUsername = parentUser.UserName,
                        Message = $"Xác nhận mật khẩu phụ huynh ({parentUser.UserName}) thành công! Cho phép đăng xuất."
                    });
                }
            }

            // Nếu thiết bị của trẻ chưa được phụ huynh nào gán ChildUsername, cho phép bất kỳ tài khoản Parent/Admin hợp lệ mở khóa
            if (candidateParentNames.Count == 0)
            {
                var parents = await _userManager.GetUsersInRoleAsync(AppRoles.Parent);
                var admins = await _userManager.GetUsersInRoleAsync(AppRoles.Admin);
                foreach (var p in parents.Concat(admins))
                {
                    if (await _userManager.CheckPasswordAsync(p, model.ParentPassword))
                    {
                        return Ok(new
                        {
                            Status = true,
                            ParentUsername = p.UserName,
                            Message = $"Xác nhận mật khẩu phụ huynh ({p.UserName}) thành công! Cho phép đăng xuất."
                        });
                    }
                }
            }

            return BadRequest(new
            {
                Status = false,
                Message = candidateParentNames.Count > 0
                    ? $"Mật khẩu của phụ huynh ({string.Join(", ", candidateParentNames)}) không chính xác!"
                    : "Mật khẩu phụ huynh không chính xác!"
            });
        }

        // ================== HÀM PHỤ ==================

        private async Task<IActionResult> IssueTokenAsync(User user, string message, double? similarity = null)
        {
            var roles = await _userManager.GetRolesAsync(user);
            var primaryRole = TokenService.GetPrimaryRole(roles);
            var token = _tokenService.GenerateToken(user, primaryRole);

            return Ok(new
            {
                Status = true,
                Message = message,
                Token = token,
                Role = primaryRole,
                Username = user.UserName,
                Similarity = similarity
            });
        }

        private async Task<(bool ok, string message)> ConfirmEmailCoreAsync(string email, string code)
        {
            var user = string.IsNullOrWhiteSpace(email) ? null : await _userManager.FindByEmailAsync(email);
            if (user == null) return (false, "Mã xác minh không hợp lệ!");
            if (user.EmailConfirmed) return (true, "Email đã được xác minh trước đó.");

            var result = await _otpService.VerifyAsync(user, OtpPurposes.ConfirmEmail, code);
            if (result != OtpVerifyResult.Success) return (false, OtpService.Describe(result));

            user.EmailConfirmed = true;
            await _userManager.UpdateAsync(user);
            return (true, "Xác minh email thành công! Bạn có thể đăng nhập.");
        }

        private async Task<bool> SendConfirmEmailAsync(User user)
        {
            var code = await _otpService.GenerateAsync(user, OtpPurposes.ConfirmEmail, ConfirmEmailLifetime);
            var baseUrl = _configuration["App:PublicBaseUrl"];
            if (string.IsNullOrWhiteSpace(baseUrl)) baseUrl = $"{Request.Scheme}://{Request.Host}";
            var link = $"{baseUrl.TrimEnd('/')}/api/Authenticate/confirm-email?email={Uri.EscapeDataString(user.Email!)}&code={code}";

            var body =
                $"<h3>Chào mừng {WebUtility.HtmlEncode(user.UserName)} đến với KidGuard!</h3>" +
                $"<p>Mã xác minh email của bạn là:</p>" +
                $"<p style='color:#2e7d32;font-size:28px;font-weight:bold;letter-spacing:6px'>{code}</p>" +
                $"<p>Hoặc bấm vào liên kết sau để xác minh: <a href='{link}'>Xác minh email</a></p>" +
                $"<p>Mã có hiệu lực trong {ConfirmEmailLifetime.TotalMinutes} phút.</p>";

            try
            {
                await _emailSender.SendAsync(user.Email!, "[KidGuard] Xác minh địa chỉ email", body);
                return true;
            }
            catch (Exception)
            {
                return false;
            }
        }

        private IActionResult LockedOut(User user)
        {
            var minutes = user.LockoutEnd.HasValue
                ? Math.Max(1, (int)Math.Ceiling((user.LockoutEnd.Value - DateTimeOffset.UtcNow).TotalMinutes))
                : 5;
            return StatusCode(StatusCodes.Status423Locked,
                new { Status = false, Message = $"Tài khoản tạm khóa do đăng nhập sai nhiều lần. Thử lại sau {minutes} phút!" });
        }

        private IActionResult EmailNotConfigured() =>
            StatusCode(StatusCodes.Status503ServiceUnavailable, new
            {
                Status = false,
                Message = "Máy chủ chưa cấu hình gửi email (SmtpSettings). Vui lòng liên hệ quản trị viên!"
            });

        private static string MaskEmail(string email)
        {
            var at = email.IndexOf('@');
            if (at <= 1) return email;
            var name = email[..at];
            var visible = name.Length <= 3 ? name[..1] : name[..2];
            return $"{visible}{new string('*', Math.Max(3, name.Length - visible.Length))}{email[at..]}";
        }
    }
}
