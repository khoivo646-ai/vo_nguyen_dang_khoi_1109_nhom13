using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using nhom13.Models;

namespace nhom13.Controllers
{
    /// <summary>
    /// Chỉ Admin được truy cập: quản lý người dùng và cấp quyền (Admin / Parent / Child).
    /// </summary>
    [Route("api/[controller]")]
    [ApiController]
    [Authorize(Roles = AppRoles.Admin)]
    public class AdminController : ControllerBase
    {
        private readonly UserManager<User> _userManager;

        public AdminController(UserManager<User> userManager)
        {
            _userManager = userManager;
        }

        // GET: api/Admin/users?search=...
        [HttpGet("users")]
        public async Task<IActionResult> GetUsers([FromQuery] string? search = null)
        {
            var query = _userManager.Users.AsNoTracking();
            if (!string.IsNullOrWhiteSpace(search))
                query = query.Where(u => u.UserName!.Contains(search) || u.Email!.Contains(search));

            var users = await query.OrderBy(u => u.UserName).Take(500).ToListAsync();
            var result = new List<object>();
            foreach (var u in users)
            {
                var roles = await _userManager.GetRolesAsync(u);
                result.Add(new
                {
                    u.Id,
                    Username = u.UserName,
                    u.Email,
                    u.EmailConfirmed,
                    Roles = roles,
                    HasFace = !string.IsNullOrEmpty(u.FaceEmbedding),
                    IsLockedOut = u.LockoutEnd.HasValue && u.LockoutEnd > DateTimeOffset.UtcNow
                });
            }
            return Ok(result);
        }

        // PUT: api/Admin/users/{username}/role  body: { "role": "Parent" }
        [HttpPut("users/{username}/role")]
        public async Task<IActionResult> SetRole(string username, [FromBody] SetRoleModel model)
        {
            var normalizedRole = AppRoles.Normalize(model.Role);
            if (normalizedRole == null)
                return BadRequest(new { Status = false, Message = $"Quyền không hợp lệ. Chỉ chấp nhận: {string.Join(", ", AppRoles.All)}" });

            var user = await _userManager.FindByNameAsync(username);
            if (user == null) return NotFound(new { Status = false, Message = "Không tìm thấy người dùng!" });

            if (string.Equals(user.UserName, User.Identity?.Name, StringComparison.OrdinalIgnoreCase) && normalizedRole != AppRoles.Admin)
                return BadRequest(new { Status = false, Message = "Không thể tự hạ quyền Admin của chính mình!" });

            var currentRoles = await _userManager.GetRolesAsync(user);
            if (currentRoles.Count > 0) await _userManager.RemoveFromRolesAsync(user, currentRoles);
            await _userManager.AddToRoleAsync(user, normalizedRole);

            // Đổi security stamp để vô hiệu hóa các phiên cũ liên quan tới Identity
            await _userManager.UpdateSecurityStampAsync(user);

            return Ok(new { Status = true, Message = $"Đã cấp quyền {normalizedRole} cho {user.UserName}. Người dùng cần đăng nhập lại." });
        }

        // POST: api/Admin/users (Admin tạo/cấp tài khoản mới, bỏ qua bước chờ xác minh email)
        [HttpPost("users")]
        public async Task<IActionResult> CreateUser([FromBody] CreateUserByAdminModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);

            var normalizedRole = AppRoles.Normalize(model.Role);
            if (normalizedRole == null)
                return BadRequest(new { Status = false, Message = $"Quyền không hợp lệ. Chỉ chấp nhận: {string.Join(", ", AppRoles.All)}" });

            if (await _userManager.FindByNameAsync(model.Username) != null)
                return BadRequest(new { Status = false, Message = "Tên đăng nhập đã tồn tại!" });

            if (await _userManager.FindByEmailAsync(model.Email) != null)
                return BadRequest(new { Status = false, Message = "Email này đã được sử dụng!" });

            var user = new User
            {
                UserName = model.Username.Trim(),
                Email = model.Email.Trim(),
                Initials = string.IsNullOrWhiteSpace(model.Initials) ? "KG" : model.Initials.Trim(),
                EmailConfirmed = true // Admin cấp trực tiếp nên kích hoạt luôn
            };

            var result = await _userManager.CreateAsync(user, model.Password);
            if (!result.Succeeded)
            {
                var errors = string.Join("; ", result.Errors.Select(e => e.Description));
                return BadRequest(new { Status = false, Message = $"Không tạo được tài khoản: {errors}" });
            }

            await _userManager.AddToRoleAsync(user, normalizedRole);
            return Ok(new
            {
                Status = true,
                Message = $"Đã cấp tài khoản '{user.UserName}' với quyền '{normalizedRole}' thành công!",
                Username = user.UserName,
                user.Email,
                Role = normalizedRole
            });
        }

        // DELETE: api/Admin/users/{username} (Admin xóa tài khoản)
        [HttpDelete("users/{username}")]
        public async Task<IActionResult> DeleteUser(string username)
        {
            var user = await _userManager.FindByNameAsync(username);
            if (user == null) return NotFound(new { Status = false, Message = "Không tìm thấy người dùng!" });

            if (string.Equals(user.UserName, User.Identity?.Name, StringComparison.OrdinalIgnoreCase))
                return BadRequest(new { Status = false, Message = "Không thể tự xóa tài khoản Admin đang đăng nhập!" });

            await _userManager.DeleteAsync(user);
            return Ok(new { Status = true, Message = $"Đã xóa tài khoản {username}." });
        }

        // PUT: api/Admin/users/{username}/unlock (Mở khóa tài khoản bị khóa do đăng nhập sai)
        [HttpPut("users/{username}/unlock")]
        public async Task<IActionResult> Unlock(string username)
        {
            var user = await _userManager.FindByNameAsync(username);
            if (user == null) return NotFound(new { Status = false, Message = "Không tìm thấy người dùng!" });

            await _userManager.SetLockoutEndDateAsync(user, null);
            await _userManager.ResetAccessFailedCountAsync(user);
            return Ok(new { Status = true, Message = $"Đã mở khóa tài khoản {user.UserName}." });
        }
    }
}
