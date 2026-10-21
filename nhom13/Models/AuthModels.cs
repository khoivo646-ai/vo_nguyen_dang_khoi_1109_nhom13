using System.ComponentModel.DataAnnotations;

namespace nhom13.Models
{
    public class RegistrationModel
    {
        [Required, StringLength(50, MinimumLength = 3)]
        [RegularExpression(@"^[a-zA-Z0-9._-]+$", ErrorMessage = "Username chỉ gồm chữ, số, dấu chấm, gạch dưới, gạch ngang.")]
        public string Username { get; set; } = string.Empty;

        [Required, EmailAddress]
        public string Email { get; set; } = string.Empty;

        [Required, MinLength(6)]
        public string Password { get; set; } = string.Empty;

        public string? Initials { get; set; }

        // Chỉ cho phép đăng ký với vai trò "Parent" hoặc "Child" (mặc định là "Parent").
        // KHÔNG cho phép tự chọn "Admin"; chỉ Admin mới được cấp quyền Admin qua AdminController.
        public string? Role { get; set; }
    }

    public class LoginModel
    {
        [Required]
        public string Username { get; set; } = string.Empty;

        [Required]
        public string Password { get; set; } = string.Empty;
    }

    public class VerifyOtpModel
    {
        [Required]
        public string Username { get; set; } = string.Empty;

        [Required, StringLength(6, MinimumLength = 6)]
        public string OtpCode { get; set; } = string.Empty;
    }

    public class ConfirmEmailModel
    {
        [Required, EmailAddress]
        public string Email { get; set; } = string.Empty;

        [Required, StringLength(6, MinimumLength = 6)]
        public string Code { get; set; } = string.Empty;
    }

    public class ResendConfirmationModel
    {
        [Required, EmailAddress]
        public string Email { get; set; } = string.Empty;
    }

    public class VerifyParentPasswordModel
    {
        public int? DeviceId { get; set; }

        [Required]
        public string ParentPassword { get; set; } = string.Empty;
    }

    public class CreateUserByAdminModel
    {
        [Required, StringLength(50, MinimumLength = 3)]
        [RegularExpression(@"^[a-zA-Z0-9._-]+$", ErrorMessage = "Username chỉ gồm chữ, số, dấu chấm, gạch dưới, gạch ngang.")]
        public string Username { get; set; } = string.Empty;

        [Required, EmailAddress]
        public string Email { get; set; } = string.Empty;

        [Required, MinLength(6)]
        public string Password { get; set; } = string.Empty;

        public string? Initials { get; set; }

        [Required]
        public string Role { get; set; } = AppRoles.Parent;
    }

    public class UpdateLocationModel
    {
        [Range(-90, 90)]
        public double Latitude { get; set; }

        [Range(-180, 180)]
        public double Longitude { get; set; }
    }
}
