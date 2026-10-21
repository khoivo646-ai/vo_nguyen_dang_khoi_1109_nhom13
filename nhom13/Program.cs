using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using System.Text;
using System.Threading.RateLimiting;
using nhom13.Models;
using nhom13.Repositories;
using nhom13.Services;

var builder = WebApplication.CreateBuilder(args);

// 1. Cấu hình SQL Server
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

// 2. Cấu hình Identity (nới lỏng quy tắc mật khẩu để dễ test)
builder.Services.AddIdentity<User, IdentityRole>(options =>
{
    options.Password.RequireDigit = false;
    options.Password.RequireLowercase = false;
    options.Password.RequireUppercase = false;
    options.Password.RequireNonAlphanumeric = false;
    options.Password.RequiredLength = 6;

    options.User.RequireUniqueEmail = true;
    options.SignIn.RequireConfirmedEmail = true;

    // Khóa tạm tài khoản 5 phút nếu sai mật khẩu / khuôn mặt 5 lần liên tiếp
    options.Lockout.AllowedForNewUsers = true;
    options.Lockout.MaxFailedAccessAttempts = 5;
    options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(5);
})
.AddEntityFrameworkStores<ApplicationDbContext>()
.AddDefaultTokenProviders();

// 3. Đăng ký DI cho Repository, Services & Controllers
builder.Services.AddControllers();
builder.Services.AddScoped<IChildDeviceRepository, ChildDeviceRepository>();

builder.Services.Configure<SmtpSettings>(builder.Configuration.GetSection("SmtpSettings"));
builder.Services.Configure<FaceRecognitionSettings>(builder.Configuration.GetSection("FaceRecognition"));
builder.Services.AddSingleton<IEmailSender, SmtpEmailSender>();
builder.Services.AddSingleton<FaceRecognitionService>();
builder.Services.AddScoped<OtpService>();
builder.Services.AddScoped<TokenService>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "KidGuard API - Nhóm 13", Version = "v1" });
    // Nút "Authorize" trên Swagger để dán JWT test các API được bảo vệ
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Dán JWT token (không cần chữ 'Bearer ')"
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" } },
            Array.Empty<string>()
        }
    });
});

// 4. Cấu hình CORS cho phép Flutter gọi API
builder.Services.AddCors(options =>
{
    options.AddPolicy("MyAllowOrigins", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

// 5. Cấu hình JWT Authentication
var jwtSettings = builder.Configuration.GetSection("JWTKey");
var key = Encoding.UTF8.GetBytes(jwtSettings["Secret"]!);

builder.Services.AddAuthentication(options =>
{
    // Ghi đè scheme mặc định (cookie) của AddIdentity => mọi API dùng JWT, trả 401/403 thay vì redirect
    options.DefaultScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultForbidScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(JwtBearerDefaults.AuthenticationScheme, options =>
{
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwtSettings["ValidIssuer"],
        ValidAudience = jwtSettings["ValidAudience"],
        IssuerSigningKey = new SymmetricSecurityKey(key),
        NameClaimType = "unique_name",
        RoleClaimType = "role",
        ClockSkew = TimeSpan.FromMinutes(1)
    };
    // Trả JSON tiếng Việt cho Flutter thay vì body rỗng
    options.Events = new JwtBearerEvents
    {
        OnChallenge = async context =>
        {
            context.HandleResponse();
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { Status = false, Message = "Chưa đăng nhập hoặc token đã hết hạn!" });
        },
        OnForbidden = async context =>
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            await context.Response.WriteAsJsonAsync(new { Status = false, Message = "Bạn không có quyền truy cập chức năng này!" });
        }
    };
});

builder.Services.AddAuthorization();

// 6. Giới hạn tần suất gọi API xác thực (chống dò mật khẩu / OTP / khuôn mặt): 20 request/phút/IP
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("auth", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 20, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});

var app = builder.Build();

// 7. Tự động tạo 3 Role (Admin, Parent, Child), tài khoản Admin mặc định & Dữ liệu thiết bị mẫu khi chạy lần đầu
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var context = services.GetRequiredService<ApplicationDbContext>();
    context.Database.Migrate(); // Tự động cập nhật DB nếu đã tạo Migration

    var roleManager = services.GetRequiredService<RoleManager<IdentityRole>>();
    var userManager = services.GetRequiredService<UserManager<User>>();
    foreach (var role in AppRoles.All)
    {
        if (!await roleManager.RoleExistsAsync(role))
        {
            await roleManager.CreateAsync(new IdentityRole(role));
        }
    }

    // Dọn các role cũ (Staff/Customer nếu từng tạo trước đó) và chuyển user cũ sang Parent
    foreach (var legacyRole in new[] { "Staff", "Customer" })
    {
        var existingRole = await roleManager.FindByNameAsync(legacyRole);
        if (existingRole != null)
        {
            var legacyUsers = await userManager.GetUsersInRoleAsync(legacyRole);
            foreach (var u in legacyUsers)
            {
                await userManager.RemoveFromRoleAsync(u, legacyRole);
                if ((await userManager.GetRolesAsync(u)).Count == 0)
                    await userManager.AddToRoleAsync(u, AppRoles.Parent);
            }
            await roleManager.DeleteAsync(existingRole);
        }
    }

    // Tài khoản Admin duy nhất được tạo từ cấu hình (người dùng tự đăng ký KHÔNG thể chọn Admin)
    var adminSection = builder.Configuration.GetSection("DefaultAdmin");
    var adminUsername = adminSection["Username"];
    var adminEmail = adminSection["Email"];
    var adminPassword = adminSection["Password"];
    if (!string.IsNullOrWhiteSpace(adminUsername) && !string.IsNullOrWhiteSpace(adminEmail) && !string.IsNullOrWhiteSpace(adminPassword)
        && (await userManager.GetUsersInRoleAsync(AppRoles.Admin)).Count == 0)
    {
        var admin = await userManager.FindByNameAsync(adminUsername);
        if (admin == null)
        {
            admin = new User { UserName = adminUsername, Email = adminEmail, EmailConfirmed = true, Initials = "AD" };
            var created = await userManager.CreateAsync(admin, adminPassword);
            if (!created.Succeeded)
            {
                app.Logger.LogError("Không tạo được Admin mặc định: {Errors}", string.Join("; ", created.Errors.Select(e => e.Description)));
                admin = null;
            }
        }
        if (admin != null) await userManager.AddToRoleAsync(admin, AppRoles.Admin);
    }

    if (!context.ChildDevices.Any())
    {
        context.ChildDevices.AddRange(
            new ChildDevice
            {
                ChildName = "Bé Nguyễn Minh An",
                DeviceName = "iPhone 13 Mini",
                ScreenTimeLimitMinutes = 90,
                BlockedApps = "TikTok, Roblox",
                IsLocked = false,
                Latitude = 10.8018, // HUTECH Điện Biên Phủ
                Longitude = 106.7144,
                ParentUsername = "khoi_parent"
            },
            new ChildDevice
            {
                ChildName = "Bé Trần Bảo Ngọc",
                DeviceName = "Samsung Galaxy Tab S9",
                ScreenTimeLimitMinutes = 120,
                BlockedApps = "YouTube Shorts, FreeFire",
                IsLocked = true,
                Latitude = 10.7769, // Quận 1
                Longitude = 106.7009,
                ParentUsername = "khoi_parent"
            }
        );
        await context.SaveChangesAsync();
    }
}

if (!app.Services.GetRequiredService<IEmailSender>().IsConfigured)
{
    app.Logger.LogWarning("SmtpSettings chưa được cấu hình: đăng ký / đăng nhập OTP sẽ trả lỗi 503 cho tới khi nhập Gmail + App Password.");
}


    app.UseSwagger();
    app.UseSwaggerUI();


app.UseHttpsRedirection();
app.UseCors("MyAllowOrigins");
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.Run();
