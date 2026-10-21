namespace nhom13.Models
{
    /// <summary>
    /// Danh sách 3 quyền của hệ thống:
    /// - Admin  : Quản trị viên, toàn quyền, quản lý tài khoản và phân quyền.
    /// - Parent : Phụ huynh, thêm/sửa/xóa và giám sát thiết bị của con mình.
    /// - Child  : Trẻ em, chỉ được xem thiết bị được liên kết với mình và gửi vị trí / mức tiếng ồn.
    /// </summary>
    public static class AppRoles
    {
        public const string Admin = "Admin";
        public const string Parent = "Parent";
        public const string Child = "Child";

        public const string AdminOrParent = Admin + "," + Parent;

        public static readonly string[] All = { Admin, Parent, Child };

        // Khi tự đăng ký, người dùng chỉ được chọn Parent hoặc Child (KHÔNG được chọn Admin).
        public static readonly string[] SelfRegistrable = { Parent, Child };

        public static string? Normalize(string? role) =>
            All.FirstOrDefault(r => string.Equals(r, role?.Trim(), StringComparison.OrdinalIgnoreCase));

        public static bool IsValid(string? role) => Normalize(role) != null;

        public static bool IsSelfRegistrable(string? role) =>
            SelfRegistrable.Any(r => string.Equals(r, role?.Trim(), StringComparison.OrdinalIgnoreCase));
    }
}
