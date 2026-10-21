using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace nhom13.Models
{
    public class ApplicationDbContext : IdentityDbContext<User>
    {
        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options) { }

        public DbSet<ChildDevice> ChildDevices { get; set; }
        public DbSet<NoiseEvent> NoiseEvents { get; set; }

        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);
            builder.Entity<User>().Property(u => u.Initials).HasMaxLength(10);
            builder.Entity<User>().Property(u => u.OtpCode).HasMaxLength(128);
            builder.Entity<User>().Property(u => u.OtpPurpose).HasMaxLength(32);

            builder.Entity<ChildDevice>().HasIndex(d => d.ParentUsername);
            builder.Entity<ChildDevice>().HasIndex(d => d.ChildUsername);

            builder.Entity<NoiseEvent>()
                .HasOne(n => n.ChildDevice)
                .WithMany(d => d.NoiseEvents)
                .HasForeignKey(n => n.ChildDeviceId)
                .OnDelete(DeleteBehavior.Cascade);
            builder.Entity<NoiseEvent>().HasIndex(n => new { n.ChildDeviceId, n.MeasuredAt });

            builder.HasDefaultSchema("identity");
        }
    }
}
