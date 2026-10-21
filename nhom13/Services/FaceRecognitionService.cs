using System.Runtime.InteropServices;
using FaceAiSharp;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace nhom13.Services
{
    public class FaceRecognitionSettings
    {
        // Ngưỡng cosine similarity giữa 2 vector ArcFace để coi là cùng 1 người.
        // Theo khuyến nghị của FaceAiSharp: >= 0.42 là cùng người; 0.28 - 0.42 là không chắc chắn.
        public float MatchThreshold { get; set; } = 0.42f;

        // Độ tin cậy tối thiểu của bộ phát hiện khuôn mặt
        public float MinDetectionConfidence { get; set; } = 0.6f;

        // Kích thước khuôn mặt tối thiểu (pixel) để đảm bảo ảnh đủ rõ
        public int MinFaceSizePx { get; set; } = 60;

        // Dung lượng ảnh tối đa (byte)
        public int MaxImageBytes { get; set; } = 6 * 1024 * 1024;
    }

    public record FaceExtractResult(bool Success, float[]? Embedding, string? Error);

    /// <summary>
    /// Nhận diện khuôn mặt THẬT trên backend bằng FaceAiSharp (ONNX Runtime, chạy offline):
    /// 1. SCRFD phát hiện khuôn mặt + 5 điểm landmark.
    /// 2. Căn chỉnh (align) khuôn mặt theo landmark.
    /// 3. ArcFace sinh vector đặc trưng 512 chiều.
    /// 4. So khớp bằng cosine similarity với vector đã đăng ký.
    /// </summary>
    public sealed class FaceRecognitionService : IDisposable
    {
        private readonly FaceRecognitionSettings _settings;
        private readonly Lazy<IFaceDetectorWithLandmarks> _detector;
        private readonly Lazy<IFaceEmbeddingsGenerator> _embedder;

        public FaceRecognitionService(Microsoft.Extensions.Options.IOptions<FaceRecognitionSettings> settings)
        {
            _settings = settings.Value;
            // Nạp model lần đầu khi cần (model ~65MB) để không làm chậm khởi động app.
            _detector = new Lazy<IFaceDetectorWithLandmarks>(() => FaceAiSharpBundleFactory.CreateFaceDetectorWithLandmarks(), true);
            _embedder = new Lazy<IFaceEmbeddingsGenerator>(() => FaceAiSharpBundleFactory.CreateFaceEmbeddingsGenerator(), true);
        }

        public float MatchThreshold => _settings.MatchThreshold;

        public FaceExtractResult ExtractEmbedding(string base64Image)
        {
            byte[] bytes;
            try
            {
                var raw = base64Image.Trim();
                var comma = raw.IndexOf(',');
                if (raw.StartsWith("data:", StringComparison.OrdinalIgnoreCase) && comma > 0)
                    raw = raw[(comma + 1)..];
                bytes = Convert.FromBase64String(raw);
            }
            catch (FormatException)
            {
                return new(false, null, "Dữ liệu ảnh không phải Base64 hợp lệ!");
            }

            if (bytes.Length == 0 || bytes.Length > _settings.MaxImageBytes)
                return new(false, null, $"Ảnh rỗng hoặc vượt quá {_settings.MaxImageBytes / 1024 / 1024}MB!");

            Image<Rgb24> img;
            try
            {
                img = Image.Load<Rgb24>(bytes);
            }
            catch (Exception)
            {
                return new(false, null, "Không đọc được ảnh (chỉ hỗ trợ JPEG/PNG/BMP/WebP)!");
            }

            using (img)
            {
                // Ảnh chụp từ điện thoại thường bị xoay theo EXIF => xoay lại cho đúng chiều
                img.Mutate(x => x.AutoOrient());

                // Thu nhỏ ảnh quá lớn để tăng tốc
                const int maxSide = 1280;
                if (img.Width > maxSide || img.Height > maxSide)
                {
                    img.Mutate(x => x.Resize(new ResizeOptions { Mode = ResizeMode.Max, Size = new Size(maxSide, maxSide) }));
                }

                var faces = _detector.Value.DetectFaces(img)
                    .Where(f => f.Confidence >= _settings.MinDetectionConfidence)
                    .ToList();

                if (faces.Count == 0)
                    return new(false, null, "Không tìm thấy khuôn mặt trong ảnh. Hãy chụp chính diện, đủ sáng!");
                if (faces.Count > 1)
                    return new(false, null, "Ảnh có nhiều hơn 1 khuôn mặt. Vui lòng chỉ chụp một người!");

                var face = faces[0];
                if (face.Box.Width < _settings.MinFaceSizePx || face.Box.Height < _settings.MinFaceSizePx)
                    return new(false, null, "Khuôn mặt quá nhỏ, hãy đưa camera lại gần hơn!");
                if (face.Landmarks == null || face.Landmarks.Count < 5)
                    return new(false, null, "Không xác định được các điểm đặc trưng khuôn mặt!");

                _embedder.Value.AlignFaceUsingLandmarks(img, face.Landmarks);
                var embedding = _embedder.Value.GenerateEmbedding(img);
                Normalize(embedding);
                return new(true, embedding, null);
            }
        }

        public static float CosineSimilarity(float[] a, float[] b)
        {
            if (a.Length != b.Length) return -1f;
            double dot = 0, na = 0, nb = 0;
            for (int i = 0; i < a.Length; i++)
            {
                dot += a[i] * b[i];
                na += a[i] * a[i];
                nb += b[i] * b[i];
            }
            if (na == 0 || nb == 0) return -1f;
            return (float)(dot / (Math.Sqrt(na) * Math.Sqrt(nb)));
        }

        public static string Serialize(float[] embedding) =>
            Convert.ToBase64String(MemoryMarshal.AsBytes(embedding.AsSpan()));

        public static float[]? Deserialize(string? data)
        {
            if (string.IsNullOrEmpty(data)) return null;
            try
            {
                var bytes = Convert.FromBase64String(data);
                if (bytes.Length % sizeof(float) != 0) return null;
                return MemoryMarshal.Cast<byte, float>(bytes).ToArray();
            }
            catch (FormatException)
            {
                return null;
            }
        }

        private static void Normalize(float[] v)
        {
            double norm = 0;
            foreach (var x in v) norm += x * x;
            norm = Math.Sqrt(norm);
            if (norm <= 0) return;
            for (int i = 0; i < v.Length; i++) v[i] = (float)(v[i] / norm);
        }

        public void Dispose()
        {
            if (_detector.IsValueCreated) (_detector.Value as IDisposable)?.Dispose();
            if (_embedder.IsValueCreated) (_embedder.Value as IDisposable)?.Dispose();
        }
    }
}
