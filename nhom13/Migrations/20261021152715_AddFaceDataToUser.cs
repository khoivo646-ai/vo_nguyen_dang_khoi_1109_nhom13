using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace nhom13.Migrations
{
    /// <inheritdoc />
    public partial class AddFaceDataToUser : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "FaceData",
                schema: "identity",
                table: "AspNetUsers",
                type: "nvarchar(max)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "FaceData",
                schema: "identity",
                table: "AspNetUsers");
        }
    }
}
