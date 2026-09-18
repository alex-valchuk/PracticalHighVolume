using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FlightsPlatform.AnalyticsWorker.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "analytics");

            migrationBuilder.CreateTable(
                name: "audit_log",
                schema: "analytics",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    message_id = table.Column<Guid>(type: "uuid", nullable: false),
                    event_type = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    payload = table.Column<string>(type: "text", nullable: false),
                    recorded_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_audit_log", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "consumed_messages",
                schema: "analytics",
                columns: table => new
                {
                    message_id = table.Column<Guid>(type: "uuid", nullable: false),
                    consumed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_consumed_messages", x => x.message_id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_audit_log_event_type",
                schema: "analytics",
                table: "audit_log",
                column: "event_type");

            migrationBuilder.CreateIndex(
                name: "IX_audit_log_recorded_at",
                schema: "analytics",
                table: "audit_log",
                column: "recorded_at");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "audit_log",
                schema: "analytics");

            migrationBuilder.DropTable(
                name: "consumed_messages",
                schema: "analytics");
        }
    }
}
