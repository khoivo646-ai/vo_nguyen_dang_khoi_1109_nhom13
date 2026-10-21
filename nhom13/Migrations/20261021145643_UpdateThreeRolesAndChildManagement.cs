using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace nhom13.Migrations
{
    /// <inheritdoc />
    public partial class UpdateThreeRolesAndChildManagement : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ChildUsername",
                schema: "identity",
                table: "ChildDevices",
                type: "nvarchar(max)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ChildUsername",
                schema: "identity",
                table: "ChildDevices");
        }
    }
}
