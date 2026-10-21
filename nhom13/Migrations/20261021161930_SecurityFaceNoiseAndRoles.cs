using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace nhom13.Migrations
{
    /// <inheritdoc />
    public partial class SecurityFaceNoiseAndRoles : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "FaceData",
                schema: "identity",
                table: "AspNetUsers",
                newName: "FaceEmbedding");

            migrationBuilder.AlterColumn<string>(
                name: "ParentUsername",
                schema: "identity",
                table: "ChildDevices",
                type: "nvarchar(450)",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(max)",
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "ChildUsername",
                schema: "identity",
                table: "ChildDevices",
                type: "nvarchar(450)",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(max)",
                oldNullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "LastNoiseAlertEmailAt",
                schema: "identity",
                table: "ChildDevices",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "LastNoiseAt",
                schema: "identity",
                table: "ChildDevices",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "LastNoiseDb",
                schema: "identity",
                table: "ChildDevices",
                type: "float",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "LocationUpdatedAt",
                schema: "identity",
                table: "ChildDevices",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "NoiseThresholdDb",
                schema: "identity",
                table: "ChildDevices",
                type: "float",
                nullable: false,
                defaultValue: 80.0);

            migrationBuilder.AlterColumn<string>(
                name: "OtpCode",
                schema: "identity",
                table: "AspNetUsers",
                type: "nvarchar(128)",
                maxLength: 128,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(max)",
                oldNullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "FaceRegisteredAt",
                schema: "identity",
                table: "AspNetUsers",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "OtpFailedCount",
                schema: "identity",
                table: "AspNetUsers",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "OtpPurpose",
                schema: "identity",
                table: "AspNetUsers",
                type: "nvarchar(32)",
                maxLength: 32,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "NoiseEvents",
                schema: "identity",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    ChildDeviceId = table.Column<int>(type: "int", nullable: false),
                    Decibel = table.Column<double>(type: "float", nullable: false),
                    PeakDecibel = table.Column<double>(type: "float", nullable: true),
                    DurationSeconds = table.Column<int>(type: "int", nullable: false),
                    ThresholdDb = table.Column<double>(type: "float", nullable: false),
                    IsAlert = table.Column<bool>(type: "bit", nullable: false),
                    IsAcknowledged = table.Column<bool>(type: "bit", nullable: false),
                    MeasuredAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NoiseEvents", x => x.Id);
                    table.ForeignKey(
                        name: "FK_NoiseEvents_ChildDevices_ChildDeviceId",
                        column: x => x.ChildDeviceId,
                        principalSchema: "identity",
                        principalTable: "ChildDevices",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ChildDevices_ChildUsername",
                schema: "identity",
                table: "ChildDevices",
                column: "ChildUsername");

            migrationBuilder.CreateIndex(
                name: "IX_ChildDevices_ParentUsername",
                schema: "identity",
                table: "ChildDevices",
                column: "ParentUsername");

            migrationBuilder.CreateIndex(
                name: "IX_NoiseEvents_ChildDeviceId_MeasuredAt",
                schema: "identity",
                table: "NoiseEvents",
                columns: new[] { "ChildDeviceId", "MeasuredAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "NoiseEvents",
                schema: "identity");

            migrationBuilder.DropIndex(
                name: "IX_ChildDevices_ChildUsername",
                schema: "identity",
                table: "ChildDevices");

            migrationBuilder.DropIndex(
                name: "IX_ChildDevices_ParentUsername",
                schema: "identity",
                table: "ChildDevices");

            migrationBuilder.DropColumn(
                name: "LastNoiseAlertEmailAt",
                schema: "identity",
                table: "ChildDevices");

            migrationBuilder.DropColumn(
                name: "LastNoiseAt",
                schema: "identity",
                table: "ChildDevices");

            migrationBuilder.DropColumn(
                name: "LastNoiseDb",
                schema: "identity",
                table: "ChildDevices");

            migrationBuilder.DropColumn(
                name: "LocationUpdatedAt",
                schema: "identity",
                table: "ChildDevices");

            migrationBuilder.DropColumn(
                name: "NoiseThresholdDb",
                schema: "identity",
                table: "ChildDevices");

            migrationBuilder.DropColumn(
                name: "FaceRegisteredAt",
                schema: "identity",
                table: "AspNetUsers");

            migrationBuilder.DropColumn(
                name: "OtpFailedCount",
                schema: "identity",
                table: "AspNetUsers");

            migrationBuilder.DropColumn(
                name: "OtpPurpose",
                schema: "identity",
                table: "AspNetUsers");

            migrationBuilder.RenameColumn(
                name: "FaceEmbedding",
                schema: "identity",
                table: "AspNetUsers",
                newName: "FaceData");

            migrationBuilder.AlterColumn<string>(
                name: "ParentUsername",
                schema: "identity",
                table: "ChildDevices",
                type: "nvarchar(max)",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(450)",
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "ChildUsername",
                schema: "identity",
                table: "ChildDevices",
                type: "nvarchar(max)",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(450)",
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "OtpCode",
                schema: "identity",
                table: "AspNetUsers",
                type: "nvarchar(max)",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "nvarchar(128)",
                oldMaxLength: 128,
                oldNullable: true);
        }
    }
}

