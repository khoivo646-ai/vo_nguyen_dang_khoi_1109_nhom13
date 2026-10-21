using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;

namespace nhom13.Services
{
    public class SmtpSettings
    {
        public string Host { get; set; } = "smtp.gmail.com";
        public int Port { get; set; } = 587;
        public string SenderEmail { get; set; } = string.Empty;
        public string SenderName { get; set; } = "KidGuard - Quản Lý Điện Thoại Trẻ Em";

        // Với Gmail: dùng "App Password" 16 ký tự (bật xác minh 2 bước trong tài khoản Google).
        public string AppPassword { get; set; } = string.Empty;

        public bool IsConfigured =>
            !string.IsNullOrWhiteSpace(SenderEmail) &&
            !string.IsNullOrWhiteSpace(AppPassword) &&
            !SenderEmail.Contains("your_email", StringComparison.OrdinalIgnoreCase) &&
            !AppPassword.Contains("your_", StringComparison.OrdinalIgnoreCase);
    }

    public interface IEmailSender
    {
        bool IsConfigured { get; }
        Task SendAsync(string toEmail, string subject, string htmlBody, CancellationToken ct = default);
    }

    /// <summary>
    /// Gửi email qua SMTP bằng MailKit. Ném exception nếu chưa cấu hình hoặc gửi thất bại
    /// để controller trả lỗi rõ ràng (KHÔNG còn trả OTP về client như trước).
    /// </summary>
    public class SmtpEmailSender : IEmailSender
    {
        private readonly SmtpSettings _settings;
        private readonly ILogger<SmtpEmailSender> _logger;

        public SmtpEmailSender(IOptions<SmtpSettings> settings, ILogger<SmtpEmailSender> logger)
        {
            _settings = settings.Value;
            _logger = logger;
        }

        public bool IsConfigured => _settings.IsConfigured;

        public async Task SendAsync(string toEmail, string subject, string htmlBody, CancellationToken ct = default)
        {
            if (!_settings.IsConfigured)
                throw new InvalidOperationException("SMTP chưa được cấu hình (SmtpSettings:SenderEmail / AppPassword).");

            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(_settings.SenderName, _settings.SenderEmail));
            message.To.Add(MailboxAddress.Parse(toEmail));
            message.Subject = subject;
            message.Body = new BodyBuilder { HtmlBody = htmlBody }.ToMessageBody();

            using var client = new SmtpClient();
            try
            {
                var socketOptions = _settings.Port == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
                await client.ConnectAsync(_settings.Host, _settings.Port, socketOptions, ct);
                await client.AuthenticateAsync(_settings.SenderEmail, _settings.AppPassword, ct);
                await client.SendAsync(message, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Gửi email tới {Email} thất bại", toEmail);
                throw;
            }
            finally
            {
                if (client.IsConnected) await client.DisconnectAsync(true, ct);
            }
        }
    }
}
