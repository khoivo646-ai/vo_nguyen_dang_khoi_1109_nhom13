using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using nhom13.Models;

namespace nhom13.Services
{
    public class TokenService
    {
        private readonly IConfiguration _configuration;

        public TokenService(IConfiguration configuration)
        {
            _configuration = configuration;
        }

        /// <summary>
        /// Chọn role chính khi user có nhiều role: Admin > Parent > Child.
        /// </summary>
        public static string GetPrimaryRole(IEnumerable<string> roles)
        {
            var list = roles.ToList();
            if (list.Contains(AppRoles.Admin)) return AppRoles.Admin;
            if (list.Contains(AppRoles.Parent)) return AppRoles.Parent;
            if (list.Contains(AppRoles.Child)) return AppRoles.Child;
            return AppRoles.Parent;
        }

        public string GenerateToken(User user, string role)
        {
            var jwtSettings = _configuration.GetSection("JWTKey");
            var authSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings["Secret"]!));

            // Claim "role" và "unique_name" là tên ngắn trong JWT, Flutter đọc trực tiếp decodedToken['role'].
            var claims = new List<Claim>
            {
                new(JwtRegisteredClaimNames.Sub, user.Id),
                new(JwtRegisteredClaimNames.UniqueName, user.UserName!),
                new(JwtRegisteredClaimNames.Email, user.Email ?? ""),
                new("role", role),
                new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
            };

            var tokenDescriptor = new SecurityTokenDescriptor
            {
                Subject = new ClaimsIdentity(claims),
                Expires = DateTime.UtcNow.AddHours(Convert.ToDouble(jwtSettings["TokenExpiryTimeInHour"] ?? "24")),
                Issuer = jwtSettings["ValidIssuer"],
                Audience = jwtSettings["ValidAudience"],
                SigningCredentials = new SigningCredentials(authSigningKey, SecurityAlgorithms.HmacSha256)
            };

            var tokenHandler = new JwtSecurityTokenHandler();
            tokenHandler.OutboundClaimTypeMap.Clear();
            return tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));
        }
    }
}
